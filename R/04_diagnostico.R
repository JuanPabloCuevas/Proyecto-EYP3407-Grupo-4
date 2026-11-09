# =============================================================================
# R/04_diagnostico.R · Sección 4: diagnóstico de errores y análisis de sensibilidad
# Usa los objetos de las secciones 1 a 3. El diagnóstico describe la prueba ya evaluada
# y no se usa para cambiar modelos, variables ni hiperparámetros. Las dos sensibilidades
# se definen y calculan con los datos de desarrollo (enunciado 3.3).
# =============================================================================

orden_modelos <- c("referencia", "referencia_ultima", "lasso", "gam", "bosque")

a_lo_ancho <- function(d, id, nombre, valor) {
  w <- reshape(as.data.frame(d[, c(id, nombre, valor)]), idvar = id, timevar = nombre,
               direction = "wide")
  names(w) <- sub(paste0("^", valor, "\\."), "", names(w))
  rownames(w) <- NULL
  w
}

# MAE de cada procedimiento por grupo (mismas filas para todos) y diferencias del lasso.
mae_por_grupo <- function(d, grupo) {
  largo <- d |>
    group_by(grupo = .data[[grupo]], modelo) |>
    summarise(n = n(), MAE = mean(abs(y - pred)), .groups = "drop")
  stopifnot(all(largo |> group_by(grupo) |> summarise(k = n_distinct(n)) |> pull(k) == 1))
  a_lo_ancho(largo, c("grupo", "n"), "modelo", "MAE") |>
    select(grupo, n, all_of(orden_modelos)) |>
    mutate(lasso_menos_ref = lasso - referencia,
           lasso_menos_ultima = lasso - referencia_ultima) |>
    rename(!!grupo := grupo)
}

# -----------------------------------------------------------------------------
# 1. Diagnóstico en prueba (2023-2024)
# -----------------------------------------------------------------------------
pred_p <- res_prueba$pred |>
  left_join(select(prueba, osebuildingid, datayear, propertygfatotal, ultima_eui, uso_prev),
            by = c("osebuildingid", "datayear"))

# a) Por tipo de edificio.
diag_tipo <- mae_por_grupo(pred_p, "buildingtype")
guardar(diag_tipo, "diag_prueba_tipo.csv")

# a2) Por uso principal (último registro <= a - 2), como pide la ficha. Conservan su
#     nombre los usos con al menos 300 filas en el entrenamiento final, una regla que no
#     mira la prueba; los demás forman "Otros usos".
usos_frecuentes <- names(which(table(dev$uso_prev) >= 300))
pred_p$uso_grupo <- ifelse(is.na(pred_p$uso_prev), "Sin uso previo",
                           ifelse(pred_p$uso_prev %in% usos_frecuentes, pred_p$uso_prev, "Otros usos"))
diag_uso <- mae_por_grupo(pred_p, "uso_grupo")
guardar(diag_uso, "diag_prueba_uso.csv")

# b) Por tamaño: quintiles de superficie estimados con el entrenamiento final.
cortes_sup <- unname(quantile(dev$propertygfatotal, 1:4 / 5))
etiquetas_sup <- c(sprintf("Q1: < %.0f", cortes_sup[1]),
                   sprintf("Q%d: %.0f a %.0f", 2:4, cortes_sup[1:3], cortes_sup[2:4]),
                   sprintf("Q5: >= %.0f", cortes_sup[4]))
pred_p$tamano_pie2 <- as.character(cut(pred_p$propertygfatotal, c(-Inf, cortes_sup, Inf),
                                       labels = etiquetas_sup, right = FALSE))
diag_tamano <- mae_por_grupo(pred_p, "tamano_pie2")
guardar(diag_tamano, "diag_prueba_tamano.csv")

# c) Por historia disponible (edificios conocidos frente a nuevos).
diag_historia <- mae_por_grupo(pred_p, "historia")
guardar(diag_historia, "diag_prueba_historia.csv")

# d) Consumo extremo conocido: última EUI válida >= percentil 99 del entrenamiento.
umbral_alto <- unname(quantile(dev$eui, 0.99))
pred_p$consumo_previo <- ifelse(!is.na(pred_p$ultima_eui) & pred_p$ultima_eui >= umbral_alto,
                                sprintf("Última EUI >= %.0f (p99)", umbral_alto), "Resto")
diag_extremos <- mae_por_grupo(pred_p, "consumo_previo")
guardar(diag_extremos, "diag_prueba_extremos.csv")
sesgo_extremos <- pred_p |>
  group_by(consumo_previo, modelo) |>
  summarise(n = n(), mediana_pred_menos_y = median(pred - y), .groups = "drop")
guardar(sesgo_extremos, "diag_prueba_extremos_sesgo.csv")

# e) Mayores errores del procedimiento elegido y peso del 1 % de errores más grandes.
ref_p <- filter(pred_p, modelo == "referencia") |> select(osebuildingid, datayear, pred_ref = pred)
mayores_errores <- pred_p |>
  filter(modelo == procedimiento_elegido$modelo) |>
  left_join(ref_p, by = c("osebuildingid", "datayear")) |>
  mutate(error_abs = abs(y - pred)) |>
  arrange(desc(error_abs)) |>
  select(osebuildingid, datayear, buildingtype, uso_prev, historia, ultima_eui, y, pred,
         pred_ref, error_abs) |>
  head(15)
guardar(mayores_errores, "diag_prueba_mayores_errores.csv")
concentracion <- pred_p |>
  mutate(ea = abs(y - pred)) |>
  arrange(modelo, desc(ea)) |>
  group_by(modelo) |>
  summarise(n = n(), filas_top1 = ceiling(0.01 * n()),
            parte_MAE_top1 = sum(ea[seq_len(filas_top1)]) / sum(ea),
            parte_cuadrados_top1 = sum(ea[seq_len(filas_top1)]^2) / sum(ea^2),
            MAE_sin_top1 = mean(ea[-seq_len(filas_top1)]), .groups = "drop")
guardar(concentracion, "diag_prueba_concentracion.csv")

# f) Error por edificio (cada edificio pesa igual) y error normalizado por la mediana
#    de su tipo estimada en el entrenamiento final (enunciado 4.2).
nivel_tipo <- dev |> group_by(buildingtype) |> summarise(nivel_tipo = median(eui), .groups = "drop")
error_entidad <- pred_p |>
  left_join(nivel_tipo, by = "buildingtype") |>
  mutate(ea = abs(y - pred), ea_rel = ea / nivel_tipo) |>
  group_by(modelo) |>
  summarise(error_relativo_tipo = mean(ea_rel), .groups = "drop") |>
  left_join(pred_p |>
              group_by(modelo, osebuildingid) |>
              summarise(mae_e = mean(abs(y - pred)), .groups = "drop") |>
              group_by(modelo) |>
              summarise(edificios = n(), MAE_por_edificio = mean(mae_e),
                        mediana_por_edificio = median(mae_e),
                        p90_por_edificio = unname(quantile(mae_e, 0.9)), .groups = "drop"),
            by = "modelo") |>
  arrange(match(modelo, orden_modelos))
guardar(error_entidad, "diag_prueba_por_edificio.csv")

# -----------------------------------------------------------------------------
# 2. Pandemia y choques comunes por año (2017-2021 desarrollo; 2023-2024 prueba)
# -----------------------------------------------------------------------------
cambio_todos <- bind_rows(select(dev, datayear, buildingtype, eui, eui_a2),
                          select(prueba, datayear, buildingtype, eui, eui_a2)) |>
  filter(!is.na(eui_a2)) |>
  mutate(cambio = log(eui / eui_a2))
cambio_por_anio <- cambio_todos |>
  group_by(anio = datayear) |>
  summarise(n = n(), mediana = median(cambio), q1 = quantile(cambio, 0.25),
            q3 = quantile(cambio, 0.75), p10 = quantile(cambio, 0.10), .groups = "drop")
guardar(cambio_por_anio, "pandemia_cambio_por_anio.csv")
cambio_por_tipo <- cambio_todos |>
  group_by(buildingtype, anio = datayear) |>
  summarise(mediana = median(cambio), .groups = "drop") |>
  a_lo_ancho("buildingtype", "anio", "mediana")
guardar(cambio_por_tipo, "pandemia_cambio_por_tipo.csv")

# MAE por año objetivo: ventanas de desarrollo (cada una entrenada hasta a-2) y prueba.
ref_ultima_dev <- bind_rows(lapply(cortes, function(corte) {
  entren <- filter(dev, datayear <= corte)
  valid <- filter(dev, datayear == corte + 2)
  transmute(valid, modelo = "referencia_ultima", osebuildingid, datayear, y = eui,
            pred = predecir_referencia_ultima(entren, valid))
}))
pred_anios <- bind_rows(
  select(pred_elegidos, modelo, osebuildingid, datayear, y, pred),
  ref_ultima_dev,
  select(res_prueba$pred, modelo, osebuildingid, datayear, y, pred))
mae_por_anio <- pred_anios |>
  group_by(anio = datayear, modelo) |>
  summarise(n = n(), MAE = mean(abs(y - pred)), .groups = "drop") |>
  a_lo_ancho(c("anio", "n"), "modelo", "MAE") |>
  select(anio, n, all_of(orden_modelos)) |>
  mutate(conjunto = ifelse(anio <= 2021, "desarrollo", "prueba"),
         lasso_menos_ref = lasso - referencia)
guardar(mae_por_anio, "pandemia_mae_por_anio.csv")

# -----------------------------------------------------------------------------
# 3. Sensibilidad S1 (preparación): respuesta original frente a logarítmica
# -----------------------------------------------------------------------------
# Se repite la búsqueda de la sección 2 con la EUI sin transformar. La historia entra
# también sin log, su forma natural en esa escala; el bosque no cambia con una
# transformación monótona de los predictores. Mismas ventanas, filas y presupuesto.
# Sin log, los modelos estiman la media condicional (mínimos cuadrados), no la mediana.
preparar_original <- function(entren, nuevos) {
  p <- preparar(entren, nuevos)
  med_eui <- median(entren$eui)
  agregar_hist <- function(x) {
    mutate(x, hist = ifelse(sin_historia, med_eui, ultima_eui),
           a3 = ifelse(is.na(eui_a3), hist, eui_a3))
  }
  list(entren = agregar_hist(p$entren), nuevos = agregar_hist(p$nuevos))
}
predictores_orig <- c("hist", "a3", setdiff(predictores, c("log_hist", "log_a3")))
matriz_orig <- function(d) {
  x <- model.matrix(reformulate(predictores_orig), d)[, -1]
  stopifnot(nrow(x) == nrow(d))
  x
}
a_original <- function(f) {
  texto <- paste(deparse(f, width.cutoff = 500), collapse = " ")
  texto <- gsub("log_a3", "a3", gsub("log_hist", "hist", sub("^log_eui", "eui", texto)))
  as.formula(texto)
}
formulas_gam_orig <- lapply(formulas_gam, a_original)
formula_bosque_orig <- reformulate(predictores, response = "eui")
p1o <- preparar_original(filter(dev, datayear <= cortes[1]),
                         filter(dev, datayear == cortes[1] + 2))
lambda_max_orig <- max(glmnet(matriz_orig(p1o$entren), p1o$entren$eui, alpha = 1)$lambda)
grilla_lambda_orig <- exp(seq(log(lambda_max_orig), log(lambda_max_orig / 1000),
                              length.out = 20))

s1_pred <- list()
for (corte in cortes) {
  ventana <- corte + 2
  p <- preparar_original(filter(dev, datayear <= corte), filter(dev, datayear == ventana))
  filas_s1 <- transmute(p$nuevos, ventana = ventana, osebuildingid, datayear, y = eui)
  x_e <- matriz_orig(p$entren)
  x_n <- matriz_orig(p$nuevos)
  stopifnot(identical(colnames(x_e), colnames(x_n)))
  pl <- predict(glmnet(x_e, p$entren$eui, alpha = 1, lambda = grilla_lambda_orig), newx = x_n)
  for (j in seq_along(grilla_lambda_orig)) {
    s1_pred[[length(s1_pred) + 1]] <- mutate(filas_s1, modelo = "lasso",
      config = sprintf("lambda=%.4g", grilla_lambda_orig[j]), complejidad = j, pred = pl[, j])
  }
  for (g in names(formulas_gam_orig)) {
    f <- gam(formulas_gam_orig[[g]], data = p$entren, method = "REML")
    s1_pred[[length(s1_pred) + 1]] <- mutate(filas_s1, modelo = "gam", config = g,
      complejidad = match(g, names(formulas_gam_orig)),
      pred = as.numeric(predict(f, newdata = p$nuevos)))
  }
  for (k in seq_len(nrow(grilla_bosque))) {
    f <- ranger(formula_bosque_orig, data = p$entren, num.trees = ARBOLES,
                mtry = grilla_bosque$mtry[k], min.node.size = grilla_bosque$min.node.size[k],
                respect.unordered.factors = "order", seed = 3407, num.threads = 1)
    s1_pred[[length(s1_pred) + 1]] <- mutate(filas_s1, modelo = "bosque",
      config = sprintf("mtry=%d, nodo=%d", grilla_bosque$mtry[k], grilla_bosque$min.node.size[k]),
      complejidad = NA, pred = predict(f, data = p$nuevos)$predictions)
  }
}
s1_pred <- bind_rows(s1_pred)
stopifnot(all(s1_pred |> count(modelo, config) |> pull(n) == nrow(pred_dev)))
s1_busqueda <- s1_pred |>
  group_by(modelo, config, complejidad) |>
  summarise(n = n(), MAE = mean(abs(y - pred)), RMSE = sqrt(mean((y - pred)^2)),
            predicciones_negativas = sum(pred < 0), .groups = "drop")
guardar(s1_busqueda, "s1_busqueda_original.csv")
s1_elegidos <- s1_busqueda |>
  group_by(modelo) |>
  arrange(MAE, complejidad, .by_group = TRUE) |>
  slice(1) |>
  ungroup()
mae_ref_dev <- mean(abs(pred_dev$y - pred_dev$pred))
s1_comparacion <- bind_rows(
  comparacion |> filter(modelo != "referencia") |>
    transmute(escala = "log", modelo, config, MAE, RMSE, dif_MAE_vs_ref,
              predicciones_negativas = 0L),
  s1_elegidos |> transmute(escala = "original", modelo, config, MAE, RMSE,
                           dif_MAE_vs_ref = MAE - mae_ref_dev, predicciones_negativas)
) |>
  arrange(match(modelo, orden_modelos), escala)
guardar(s1_comparacion, "s1_comparacion.csv")
guardar(semi_join(s1_pred, s1_elegidos, by = c("modelo", "config")) |> select(-complejidad),
        "s1_predicciones_original.csv")

# -----------------------------------------------------------------------------
# 4. Sensibilidad S2 (validación y población): edificios excluidos del ajuste
# -----------------------------------------------------------------------------
# El 20 % de los edificios de desarrollo, elegido al azar con semilla fija, sale
# completo de todos los entrenamientos. Se comparan, en las mismas filas de validación,
# las predicciones con y sin esos edificios en el ajuste. Si el modelo dependiera de
# haber visto al edificio, su error subiría en los excluidos.
set.seed(3407)
edificios_dev <- sort(unique(dev$osebuildingid))
excluidos <- sample(edificios_dev, round(0.2 * length(edificios_dev)))
s2_pred <- bind_rows(lapply(cortes, function(corte) {
  entren <- filter(dev, datayear <= corte, !osebuildingid %in% excluidos)
  valid <- filter(dev, datayear == corte + 2)
  predecir_todos(entren, valid)$pred
}))
pred_con_todos <- bind_rows(select(pred_elegidos, modelo, osebuildingid, datayear, pred),
                            select(ref_ultima_dev, modelo, osebuildingid, datayear, pred))
s2_filas <- s2_pred |>
  inner_join(pred_con_todos, by = c("modelo", "osebuildingid", "datayear"),
             suffix = c("_sin", "_con")) |>
  mutate(grupo = ifelse(osebuildingid %in% excluidos, "Excluidos del ajuste", "Incluidos"))
guardar(select(s2_filas, modelo, osebuildingid, datayear, grupo, y, pred_sin, pred_con),
        "s2_predicciones.csv")
s2_comparacion <- s2_filas |>
  group_by(modelo, grupo) |>
  summarise(n = n(), edificios = n_distinct(osebuildingid),
            MAE_con_todos = mean(abs(y - pred_con)),
            MAE_sin_excluidos = mean(abs(y - pred_sin)),
            cambio = MAE_sin_excluidos - MAE_con_todos, .groups = "drop") |>
  arrange(grupo, match(modelo, orden_modelos))
stopifnot(sum(s2_comparacion$n[s2_comparacion$modelo == "lasso"]) == nrow(pred_dev))
guardar(s2_comparacion, "s2_edificios_excluidos.csv")

# -----------------------------------------------------------------------------
# 5. Control de la regla de errores de registro
# -----------------------------------------------------------------------------
# Se rehace la base sin la regla y se reajustan los procedimientos elegidos en las tres
# ventanas. Se evalúa en todas las filas de esa versión y en las filas válidas con regla.
pred_sin_regla <- local({
  APLICAR_REGLA <- FALSE
  SALIDA <- file.path(SALIDA, "sin_regla")
  source("R/01_base.R", local = TRUE)
  bind_rows(lapply(cortes, function(corte) {
    predecir_todos(filter(dev, datayear <= corte), filter(dev, datayear == corte + 2))$pred
  }))
})
pred_con_regla <- bind_rows(select(pred_elegidos, modelo, osebuildingid, datayear, y, pred),
                            ref_ultima_dev)
control_regla <- bind_rows(
  pred_con_regla |> group_by(modelo) |> resumir() |> mutate(version = "Con regla"),
  pred_sin_regla |> semi_join(pred_con_regla, by = c("osebuildingid", "datayear")) |>
    group_by(modelo) |> resumir() |> mutate(version = "Sin regla, filas válidas"),
  pred_sin_regla |> group_by(modelo) |> resumir() |> mutate(version = "Sin regla, todas sus filas")
) |>
  arrange(match(modelo, orden_modelos), version)
guardar(control_regla, "control_sin_regla.csv")
guardar(select(pred_sin_regla, modelo, osebuildingid, datayear, y, pred),
        "control_sin_regla_predicciones.csv")

# -----------------------------------------------------------------------------
# 6. Figuras de diagnóstico (tamaño de impresión: 6,5 pulgadas de ancho a 300 ppp,
#    para que el texto quede legible en el informe y en las diapositivas)
# -----------------------------------------------------------------------------
col_serie <- c(lasso = "#2a78d6", referencia = "#eb6834", referencia_ultima = "#1baf7a")
pch_serie <- c(lasso = 16, referencia = 17, referencia_ultima = 15)
nombre_serie <- c(lasso = "Lasso (elegido)", referencia = "Ref.: EUI de a-2",
                  referencia_ultima = "Ref. alt.: última EUI")

# Figura 3 del informe: error por año y cambio de la EUI respecto de a-2.
png(file.path(SALIDA, "fig3_error_y_cambio_por_anio.png"), width = 6.5, height = 3.2,
    units = "in", res = 300, pointsize = 10)
par(mfrow = c(1, 2), mar = c(3.6, 4.0, 2.2, 0.6), mgp = c(2.4, 0.6, 0), las = 1,
    cex.axis = 0.85, col.axis = "#3d3d3a", fg = "#8a8a85")
anios_x <- mae_por_anio$anio
rango_y <- range(unlist(mae_por_anio[, names(col_serie)]))
lim_y <- c(floor(rango_y[1]) - 1, ceiling(rango_y[2]))
plot(NA, xlim = c(2018.6, 2024.6), ylim = lim_y,
     xaxt = "n", xlab = "Año objetivo", ylab = "MAE (kBtu/pie²)",
     main = "A. MAE por año objetivo", cex.main = 0.95, font.main = 1)
axis(1, at = c(2019:2021, 2023:2024))
abline(h = pretty(lim_y), col = "#ececea", lwd = 1)
abline(v = 2022, lty = 2, col = "#b0b0aa")
text(c(2020, 2023.5), lim_y[2], c("Desarrollo", "Prueba"), cex = 0.8, col = "#6b6b66", pos = 1)
for (m in names(col_serie)) {
  for (tramo in list(2019:2021, 2023:2024)) {
    k <- anios_x %in% tramo
    lines(anios_x[k], mae_por_anio[[m]][k], col = col_serie[[m]], lwd = 2)
  }
  points(anios_x, mae_por_anio[[m]], col = col_serie[[m]], pch = pch_serie[[m]], cex = 1.2)
}
legend("bottomleft", legend = nombre_serie[names(col_serie)], col = col_serie, pch = pch_serie,
       lwd = 2, bty = "n", cex = 0.8, text.col = "#3d3d3a")
cp <- cambio_por_anio
plot(NA, xlim = c(2016.7, 2024.3), ylim = range(c(cp$q1, cp$q3, 0)), xaxt = "n", yaxt = "n",
     xlab = "Año objetivo a", ylab = "log(EUI de a / EUI de a-2)",
     main = "B. Cambio desde a-2: mediana y RIC", cex.main = 0.95, font.main = 1)
axis(1, at = cp$anio, gap.axis = 0.1)
marcas_y <- pretty(range(c(cp$q1, cp$q3, 0)))
axis(2, at = marcas_y, labels = formatC(marcas_y, format = "f", digits = 2, decimal.mark = ","))
abline(h = 0, col = "#b0b0aa")
abline(v = 2022, lty = 2, col = "#b0b0aa")
text(c(2019, 2023.5), max(cp$q3, 0), c("Desarrollo", "Prueba"), cex = 0.8, col = "#6b6b66",
     pos = 1)
segments(cp$anio, cp$q1, cp$anio, cp$q3, col = "#555555", lwd = 2)
points(cp$anio, cp$mediana, pch = 16, col = "#3d3d3a", cex = 1.2)
dev.off()

# Figura 4 del informe: observado frente a predicho en prueba, procedimiento elegido.
pe <- filter(pred_p, modelo == procedimiento_elegido$modelo)
alto <- pe$consumo_previo != "Resto"
png(file.path(SALIDA, "fig4_observado_vs_predicho_prueba.png"), width = 4.0, height = 3.6,
    units = "in", res = 300, pointsize = 10)
par(mar = c(3.8, 4.0, 2.2, 0.6), mgp = c(2.4, 0.6, 0), las = 1, cex.axis = 0.85,
    col.axis = "#3d3d3a", fg = "#8a8a85")
lim <- range(c(pe$y, pe$pred))
plot(pe$pred[!alto], pe$y[!alto], log = "xy", xlim = lim, ylim = lim, pch = 16, cex = 0.45,
     xaxt = "n", yaxt = "n",
     col = adjustcolor("#9a9a94", 0.45),
     xlab = "EUI predicha (kBtu/pie², escala log)", ylab = "EUI observada (kBtu/pie², escala log)",
     main = sprintf("Lasso en prueba 2023\u20132024 (n = %d)", nrow(pe)), cex.main = 0.95, font.main = 1)
marcas <- c(0.1, 1, 10, 100, 1000)
axis(1, at = marcas, labels = c("0,1", "1", "10", "100", "1000"))
axis(2, at = marcas, labels = c("0,1", "1", "10", "100", "1000"))
abline(0, 1, lty = 2, col = "#3d3d3a")
points(pe$pred[alto], pe$y[alto], pch = 21, bg = "#1f1f1f", col = "#ffffff", cex = 0.95)
legend("topleft", legend = c(sprintf("Última EUI \u2265 %.0f (p99 del entrenamiento), n = %d",
                                     umbral_alto, sum(alto)),
                             sprintf("Resto, n = %d", sum(!alto)), "Predicción = observación"),
       pch = c(21, 16, NA), pt.bg = c("#1f1f1f", NA), col = c("#ffffff", "#9a9a94", "#3d3d3a"),
       lty = c(NA, NA, 2), bty = "n", cex = 0.75, text.col = "#3d3d3a")
dev.off()
