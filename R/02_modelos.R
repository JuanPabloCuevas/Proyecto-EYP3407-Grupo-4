# =============================================================================
# R/02_modelos.R · Sección 2: lasso, GAM y bosque aleatorio en las tres ventanas
# Usa los objetos creados por R/01_base.R: dev, cortes, pred_dev, resumir y guardar.
# =============================================================================

suppressPackageStartupMessages({
  library(glmnet)
  library(mgcv)
  library(ranger)
})

# Expectativas fijadas antes de ajustar (enunciado, 3.2):
# - M1 lasso: persistencia (log de la EUI previa) más ajustes aditivos por tipo, uso,
#   tamaño y barrio. Falla si los efectos no son lineales en log o cambian según el tipo.
# - M2 GAM: además, curvas suaves para historia, tamaño y antigüedad. No captura
#   interacciones; con la historia de a-2 y de a-3 juntas puede haber concurvidad.
# - M3 bosque: interacciones como tipo x historia sin especificarlas. No extrapola fuera
#   del rango visto y puede apoyarse en reconocer edificios ya vistos.
# Métrica principal: MAE reunido de las tres ventanas, en kBtu/pie²; RMSE como apoyo.
# Regla de selección: menor MAE reunido, dentro de cada familia (hiperparámetros) y entre
# familias (procedimiento elegido); un empate exacto se resuelve hacia lo más simple.
# No se usa la regla 1-EE: las tres ventanas comparten edificios y datos de entrenamiento,
# así que la desviación estándar de sus MAE dividida por raíz de 3 no es un error
# estándar (enunciado 4.3; clase S10). La variación entre ventanas se informa como
# estabilidad, y la incertidumbre de la diferencia con la referencia se estima en la
# sección 3 remuestreando edificios.
# Todos se ajustan sobre log(EUI) y se retransforman con exp(). Eso entrega la mediana
# condicional si el residuo en log tiene mediana 0; se comprueba al final, dentro y
# fuera del entrenamiento.

MIN_NIVEL <- 30  # filas de entrenamiento para que una categoría conserve su nombre

# -----------------------------------------------------------------------------
# 1. Preparación aprendida solo con el entrenamiento de cada ventana
# -----------------------------------------------------------------------------
# Categorías raras del entrenamiento van a "Otro"; un valor ausente, a "Sin dato";
# una categoría que no apareció al entrenar toma la más frecuente del entrenamiento.
nivelar <- function(v_entren, v_nuevo, min_nivel = MIN_NIVEL) {
  frecuencias <- table(v_entren)
  conservar <- names(frecuencias)[frecuencias >= min_nivel]
  agrupar <- function(v) ifelse(is.na(v), "Sin dato", ifelse(v %in% conservar, v, "Otro"))
  a <- agrupar(v_entren)
  b <- agrupar(v_nuevo)
  niveles <- sort(unique(a))
  b[!b %in% niveles] <- names(which.max(table(a)))
  list(entren = factor(a, levels = niveles), nuevo = factor(b, levels = niveles))
}

preparar <- function(entren, nuevos) {
  # Valores aprendidos en el entrenamiento y aplicados sin recalcular a la validación.
  med_log_eui <- median(log(entren$eui))
  med_frac <- median(entren$frac_uso_prev, na.rm = TRUE)
  med_n_usos <- median(entren$n_usos_prev, na.rm = TRUE)
  med_pisos <- median(entren$numberoffloors[entren$numberoffloors > 0])
  med_edif <- median(entren$numberofbuildings[entren$numberofbuildings > 0])
  transformar <- function(x) {
    x |> mutate(
      log_eui = log(eui),
      sin_hist = as.numeric(sin_historia),
      # Sin historia: nivel típico del entrenamiento, con su indicadora.
      log_hist = ifelse(sin_historia, med_log_eui, log(ultima_eui)),
      hist_antigua = as.numeric(!sin_historia & anios_desde_ultima > 2),
      # Sin EUI en a-3: se repite la última, así la diferencia entre ambas es 0.
      falta_a3 = as.numeric(is.na(eui_a3)),
      log_a3 = ifelse(is.na(eui_a3), log_hist, log(eui_a3)),
      falta_frac = as.numeric(is.na(frac_uso_prev)),
      frac_uso = coalesce(frac_uso_prev, med_frac),
      n_usos = coalesce(n_usos_prev, med_n_usos),
      # 0 pisos o 0 edificios son códigos de dato ausente.
      log_pisos = log(ifelse(numberoffloors > 0, numberoffloors, med_pisos)),
      log_edif = log(ifelse(numberofbuildings > 0, numberofbuildings, med_edif))
    )
  }
  e <- transformar(entren)
  n <- transformar(nuevos)
  nombres <- c(uso_prev = "uso", buildingtype = "tipo", neighborhood = "barrio")
  for (v in names(nombres)) {
    f <- nivelar(e[[v]], n[[v]])
    e[[nombres[[v]]]] <- f$entren
    n[[nombres[[v]]]] <- f$nuevo
  }
  list(entren = e, nuevos = n)
}

predictores <- c("log_hist", "sin_hist", "hist_antigua", "log_a3", "falta_a3", "frac_uso",
                 "falta_frac", "n_usos", "log_superficie", "frac_estacionamiento",
                 "antiguedad", "log_pisos", "log_edif", "tipo", "uso", "barrio")
formula_lineal <- reformulate(predictores)
matriz <- function(d) {
  x <- model.matrix(formula_lineal, d)[, -1]
  stopifnot(nrow(x) == nrow(d))  # ninguna fila se pierde por NA
  x
}

formulas_gam <- list(
  G1 = log_eui ~ s(log_hist) + sin_hist + hist_antigua + tipo,
  G2 = log_eui ~ s(log_hist) + sin_hist + hist_antigua + tipo + s(log_superficie) +
    s(antiguedad) + uso + barrio + frac_estacionamiento + log_pisos,
  G3 = log_eui ~ s(log_hist) + sin_hist + hist_antigua + tipo + s(log_superficie) +
    s(antiguedad) + uso + barrio + frac_estacionamiento + log_pisos + s(log_a3) +
    falta_a3 + frac_uso + falta_frac + n_usos + log_edif
)

grilla_bosque <- expand.grid(mtry = c(3, 5, 8, 12), min.node.size = c(5, 20, 50))
formula_bosque <- reformulate(predictores, response = "log_eui")
ARBOLES <- 300

# Grilla de lambda: 20 valores en escala logarítmica, fijados antes de validar con el
# entrenamiento de la primera ventana (desde el lambda que anula todo hasta 1/1000 de él).
p1 <- preparar(filter(dev, datayear <= cortes[1]), filter(dev, datayear == cortes[1] + 2))
lambda_max <- max(glmnet(matriz(p1$entren), p1$entren$log_eui, alpha = 1)$lambda)
grilla_lambda <- exp(seq(log(lambda_max), log(lambda_max / 1000), length.out = 20))

# -----------------------------------------------------------------------------
# 2. Ajuste en cada ventana y predicción de su año de validación
# -----------------------------------------------------------------------------
cronometrar <- function(expr) {
  t0 <- proc.time()[["elapsed"]]
  valor <- expr
  list(valor = valor, segundos = proc.time()[["elapsed"]] - t0)
}

predicciones <- list()
tiempos <- list()
residuo_entren <- list()  # mediana del residuo en log dentro del entrenamiento
columnas_lasso <- c()
ajustes_lasso <- list()
ajustes_gam <- list()

for (corte in cortes) {
  ventana <- corte + 2
  p <- preparar(filter(dev, datayear <= corte), filter(dev, datayear == ventana))
  filas <- p$nuevos |>
    transmute(ventana = ventana, osebuildingid, datayear, buildingtype, historia, y = eui)
  anotar <- function(modelo, config, r) {
    residuo_entren[[length(residuo_entren) + 1]] <<- data.frame(
      modelo = modelo, config = config, ventana = ventana, mediana_entren = median(r))
  }
  agregar <- function(modelo, config, complejidad, pred_log) {
    predicciones[[length(predicciones) + 1]] <<- mutate(
      filas, modelo = modelo, config = config, complejidad = complejidad,
      pred = exp(pred_log), pred_log = pred_log)
  }

  # M1: lasso, una corrida da toda la grilla de lambda.
  x_entren <- matriz(p$entren)
  x_nuevo <- matriz(p$nuevos)
  stopifnot(identical(colnames(x_entren), colnames(x_nuevo)))
  a <- cronometrar(glmnet(x_entren, p$entren$log_eui, alpha = 1, lambda = grilla_lambda))
  ajustes_lasso[[as.character(ventana)]] <- a$valor
  tiempos[[length(tiempos) + 1]] <- data.frame(modelo = "lasso", ventana = ventana,
                                               segundos = a$segundos)
  columnas_lasso[as.character(ventana)] <- ncol(x_entren)
  pl <- predict(a$valor, newx = x_nuevo)
  pe <- predict(a$valor, newx = x_entren)
  for (j in seq_along(grilla_lambda)) {
    agregar("lasso", sprintf("lambda=%.4g", grilla_lambda[j]), j, pl[, j])
    anotar("lasso", sprintf("lambda=%.4g", grilla_lambda[j]), p$entren$log_eui - pe[, j])
  }

  # M2: GAM, suavidad elegida por REML dentro de cada entrenamiento.
  for (g in names(formulas_gam)) {
    a <- cronometrar(gam(formulas_gam[[g]], data = p$entren, method = "REML"))
    ajustes_gam[[paste(g, ventana)]] <- a$valor
    tiempos[[length(tiempos) + 1]] <- data.frame(modelo = "gam", ventana = ventana,
                                                 segundos = a$segundos)
    agregar("gam", g, match(g, names(formulas_gam)),
            as.numeric(predict(a$valor, newdata = p$nuevos)))
    anotar("gam", g, residuals(a$valor, type = "response"))
  }

  # M3: bosque aleatorio. No se usa el error fuera de bolsa para elegir.
  for (k in seq_len(nrow(grilla_bosque))) {
    a <- cronometrar(ranger(formula_bosque, data = p$entren, num.trees = ARBOLES,
                            mtry = grilla_bosque$mtry[k],
                            min.node.size = grilla_bosque$min.node.size[k],
                            respect.unordered.factors = "order",
                            seed = 3407, num.threads = 1))
    tiempos[[length(tiempos) + 1]] <- data.frame(modelo = "bosque", ventana = ventana,
                                                 segundos = a$segundos)
    etiqueta <- sprintf("mtry=%d, nodo=%d", grilla_bosque$mtry[k], grilla_bosque$min.node.size[k])
    agregar("bosque", etiqueta, NA, predict(a$valor, data = p$nuevos)$predictions)
    # Dentro del entrenamiento se usa la predicción fuera de bolsa (sin ella el bosque
    # reproduce casi exactamente sus propios datos).
    anotar("bosque", etiqueta, p$entren$log_eui - a$valor$predictions)
  }
}
pred_modelos <- bind_rows(predicciones)
tiempos <- bind_rows(tiempos)
residuo_entren <- bind_rows(residuo_entren)

# Todos los modelos predicen exactamente las filas de la referencia.
stopifnot(all(pred_modelos |> count(modelo, config) |> pull(n) == nrow(pred_dev)))

# -----------------------------------------------------------------------------
# 3. Búsqueda: MAE reunido y por ventana de cada configuración
# -----------------------------------------------------------------------------
stopifnot(identical(cortes + 2, c(2019, 2020, 2021)))
mae_ventanas <- pred_modelos |>
  group_by(modelo, config) |>
  summarise(MAE_2019 = mean(abs(y - pred)[ventana == 2019]),
            MAE_2020 = mean(abs(y - pred)[ventana == 2020]),
            MAE_2021 = mean(abs(y - pred)[ventana == 2021]), .groups = "drop")
busqueda <- pred_modelos |>
  group_by(modelo, config, complejidad) |>
  resumir() |>
  left_join(mae_ventanas, by = c("modelo", "config")) |>
  arrange(modelo, complejidad, MAE)
guardar(busqueda, "busqueda_desarrollo.csv")

# Dentro de cada familia, la configuración de menor MAE reunido.
elegidos <- busqueda |>
  group_by(modelo) |>
  arrange(MAE, complejidad, .by_group = TRUE) |>
  slice(1) |>
  ungroup()

# -----------------------------------------------------------------------------
# 4. Comparación con la referencia sobre las mismas filas
# -----------------------------------------------------------------------------
pred_elegidos <- bind_rows(
  mutate(pred_dev, config = "EUI de a-2", pred_log = log(pred)),
  semi_join(pred_modelos, elegidos, by = c("modelo", "config")) |> select(-complejidad)
)
guardar(pred_elegidos, "predicciones_elegidas.csv")

dif_referencia <- pred_elegidos |>
  select(modelo, ventana, osebuildingid, datayear, y, pred) |>
  left_join(pred_dev |> select(ventana, osebuildingid, datayear, pred_ref = pred),
            by = c("ventana", "osebuildingid", "datayear"))
complejidad_texto <- c(
  lasso = sprintf("%.0f de %.0f coeficientes distintos de 0 (promedio de ventanas)",
                  mean(sapply(ajustes_lasso, function(f) {
                    lam <- grilla_lambda[elegidos$complejidad[elegidos$modelo == "lasso"]]
                    sum(coef(f, s = lam)[-1] != 0)
                  })), mean(columnas_lasso)),
  gam = sprintf("%.1f grados de libertad efectivos (promedio de ventanas)", mean(sapply(
    names(ajustes_gam)[startsWith(names(ajustes_gam),
                                  elegidos$config[elegidos$modelo == "gam"])],
    function(k) sum(ajustes_gam[[k]]$edf)))),
  bosque = sprintf("%d árboles; %s", ARBOLES, elegidos$config[elegidos$modelo == "bosque"]),
  referencia = "sin parámetros"
)
comparacion <- dif_referencia |>
  group_by(modelo) |>
  summarise(n = n(), MAE = mean(abs(y - pred)), RMSE = sqrt(mean((y - pred)^2)),
            dif_MAE_vs_ref = MAE - mean(abs(y - pred_ref)),
            MAE_2019 = mean(abs(y - pred)[ventana == 2019]),
            MAE_2020 = mean(abs(y - pred)[ventana == 2020]),
            MAE_2021 = mean(abs(y - pred)[ventana == 2021]),
            .groups = "drop") |>
  left_join(select(elegidos, modelo, config), by = "modelo") |>
  mutate(config = coalesce(config, "EUI de a-2"),
         complejidad = unname(complejidad_texto[modelo])) |>
  arrange(MAE)
guardar(comparacion, "comparacion_desarrollo.csv")

# Costo computacional de toda la búsqueda (3 ventanas). Va en un archivo aparte porque
# los segundos cambian entre corridas; todos los demás resultados deben repetirse exactos.
costo <- tiempos |>
  group_by(modelo) |>
  summarise(ajustes = n(), segundos_busqueda = round(sum(segundos), 1), .groups = "drop")
guardar(costo, "tiempos_busqueda.csv")

dif_por_ventana <- dif_referencia |>
  group_by(modelo, ventana) |>
  summarise(dif_MAE_vs_ref = mean(abs(y - pred)) - mean(abs(y - pred_ref)), .groups = "drop")
guardar(dif_por_ventana, "diferencia_por_ventana.csv")

# Procedimiento elegido: menor MAE reunido entre las tres familias; un empate exacto
# va al más simple (lasso < GAM < bosque). La referencia no compite: es la vara de
# comparación.
orden_simple <- c(lasso = 1, gam = 2, bosque = 3)
procedimiento_elegido <- comparacion |>
  filter(modelo != "referencia") |>
  arrange(MAE, orden_simple[modelo]) |>
  slice(1)

# -----------------------------------------------------------------------------
# 5. Comprobación de supuestos
# -----------------------------------------------------------------------------
# a) Retransformación: exp() entrega la mediana condicional si el residuo en log tiene
#    mediana 0 (la simetría basta, pero no hace falta). Se mira la mediana, la media y la
#    asimetría del residuo en log fuera de muestra,
#    y la pendiente de calibración de log(y) sobre log(predicción), que debiera ser 1.
#    La referencia se incluye como comparación (su "residuo" es log(y / predicción)).
residuos_log <- pred_elegidos |>
  mutate(r = log(y) - pred_log) |>
  group_by(modelo) |>
  summarise(mediana = median(r), media = mean(r),
            asimetria = mean((r - mean(r))^3) / sd(r)^3,
            pendiente_calibracion = coef(lm(log(y) ~ pred_log))[2],
            .groups = "drop")
guardar(residuos_log, "residuos_log.csv")
residuos_por_ventana <- pred_elegidos |>
  mutate(r = log(y) - pred_log) |>
  group_by(modelo, ventana) |>
  summarise(mediana = median(r), media = mean(r), .groups = "drop")
guardar(residuos_por_ventana, "residuos_log_por_ventana.csv")

#    Mismo residuo dentro del entrenamiento de cada ventana (bosque: fuera de bolsa). Si
#    ahí la mediana es cercana a 0, exp() entrega la mediana condicional en los años de
#    entrenamiento, y un desvío fuera de muestra viene del cambio entre años.
residuo_entren_elegidos <- semi_join(residuo_entren, elegidos, by = c("modelo", "config"))
guardar(residuo_entren_elegidos, "residuos_log_entrenamiento.csv")

#    Choque común por año: cambio de la EUI respecto de a-2 en los edificios que tienen
#    ambos valores. Si cambia de un año a otro, ningún modelo entrenado con años
#    anteriores puede anticiparlo.
cambio_anual <- dev |>
  filter(!is.na(eui_a2)) |>
  group_by(anio = datayear) |>
  summarise(n = n(), mediana_log_cambio = median(log(eui / eui_a2)),
            q1 = quantile(log(eui / eui_a2), 0.25), q3 = quantile(log(eui / eui_a2), 0.75),
            .groups = "drop")
guardar(cambio_anual, "cambio_anual_vs_a2.csv")

# b) Varianza del error en log según el nivel predicho (quintiles de la predicción).
dispersion <- pred_elegidos |>
  filter(modelo != "referencia") |>
  group_by(modelo) |>
  mutate(quintil = ntile(pred_log, 5)) |>
  group_by(modelo, quintil) |>
  summarise(n = n(), pred_mediana = median(pred), mediana_abs_residuo_log =
              median(abs(log(y) - pred_log)), .groups = "drop")
guardar(dispersion, "dispersion_por_quintil.csv")

# Error según la historia disponible (filas idénticas para todos los procedimientos).
por_historia_modelos <- pred_elegidos |>
  group_by(modelo, historia) |>
  resumir()
guardar(por_historia_modelos, "metricas_por_historia_modelos.csv")

# c) GAM elegido, ajustado con 2017-2019: suficiencia de k y concurvidad.
gam_final_ventana <- ajustes_gam[[paste(elegidos$config[elegidos$modelo == "gam"], 2021)]]
gam_k <- as.data.frame(k.check(gam_final_ventana))
gam_k$termino <- rownames(gam_k)
guardar(gam_k, "gam_k_check.csv")
# En mgcv, la columna "para" de concurvity() compara solo la columna del intercepto con
# el resto; aquí vale cerca de 1 porque las indicadoras de tipo suman 1 salvo en la
# categoría base (Hospital). La concurvidad que importa es la de cada curva s().
gam_concurvidad <- as.data.frame(concurvity(gam_final_ventana, full = TRUE))
gam_concurvidad$medida <- rownames(gam_concurvidad)
guardar(gam_concurvidad, "gam_concurvidad.csv")

# d) Estabilidad del lasso: variables con coeficiente distinto de 0 en cada ventana.
lam_elegido <- grilla_lambda[elegidos$complejidad[elegidos$modelo == "lasso"]]
lasso_variables <- bind_rows(lapply(names(ajustes_lasso), function(v) {
  b <- coef(ajustes_lasso[[v]], s = lam_elegido)
  data.frame(ventana = v, variable = rownames(b)[-1], coeficiente = as.numeric(b[-1]))
})) |>
  filter(coeficiente != 0)
guardar(lasso_variables, "lasso_variables.csv")
