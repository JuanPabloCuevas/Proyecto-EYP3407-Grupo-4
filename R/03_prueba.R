# =============================================================================
# R/03_prueba.R · Sección 3: ajuste final con objetivos 2017-2021 y prueba 2023-2024
# Usa los objetos de R/01_base.R y R/02_modelos.R. La prueba se evalúa una sola vez:
# población, regla de calidad, variables, modelos, hiperparámetros, métricas y regla
# de selección quedaron fijados en las secciones 1 y 2.
# =============================================================================

B_BOOT <- 2000  # réplicas del remuestreo por edificio

# -----------------------------------------------------------------------------
# 1. Ajuste con un entrenamiento y predicción de filas nuevas, para los cuatro
#    procedimientos con la configuración elegida en desarrollo
# -----------------------------------------------------------------------------
config_bosque <- grilla_bosque[match(
  elegidos$config[elegidos$modelo == "bosque"],
  sprintf("mtry=%d, nodo=%d", grilla_bosque$mtry, grilla_bosque$min.node.size)), ]
indice_lambda <- elegidos$complejidad[elegidos$modelo == "lasso"]
formula_gam <- formulas_gam[[elegidos$config[elegidos$modelo == "gam"]]]

# Referencia alternativa, fijada antes de mirar las respuestas de prueba: la última EUI
# válida hasta a-2 (aunque no sea la de a-2) y, sin ninguna, la mediana por tipo. Solo
# se informa; no participa en la selección. Motivo: en prueba, 631 de 7001 filas tienen
# historia anterior pero no EUI en a-2 (en desarrollo eran 75 de 10 035), porque en 2021
# y 2022 faltan 419 y 345 valores de EUI; para ellas la referencia principal usa la mediana.
predecir_referencia_ultima <- function(entren, nuevos) {
  med_tipo <- entren |>
    group_by(buildingtype) |>
    summarise(med_tipo = median(eui), .groups = "drop")
  nuevos |>
    left_join(med_tipo, by = "buildingtype") |>
    mutate(pred = coalesce(ultima_eui, med_tipo, median(entren$eui))) |>
    pull(pred)
}

predecir_todos <- function(entren, nuevos) {
  p <- preparar(entren, nuevos)
  # Lasso: se ajusta la grilla completa (como en desarrollo) y se toma el lambda elegido.
  x_entren <- matriz(p$entren)
  x_nuevo <- matriz(p$nuevos)
  stopifnot(identical(colnames(x_entren), colnames(x_nuevo)))
  f_lasso <- glmnet(x_entren, p$entren$log_eui, alpha = 1, lambda = grilla_lambda)
  f_gam <- gam(formula_gam, data = p$entren, method = "REML")
  f_bosque <- ranger(formula_bosque, data = p$entren, num.trees = ARBOLES,
                     mtry = config_bosque$mtry, min.node.size = config_bosque$min.node.size,
                     respect.unordered.factors = "order", seed = 3407, num.threads = 1)
  filas <- transmute(p$nuevos, osebuildingid, datayear, buildingtype, historia, y = eui)
  pred <- bind_rows(
    mutate(filas, modelo = "referencia", pred = predecir_referencia(entren, nuevos)),
    mutate(filas, modelo = "referencia_ultima", pred = predecir_referencia_ultima(entren, nuevos)),
    mutate(filas, modelo = "lasso",
           pred = exp(predict(f_lasso, newx = x_nuevo)[, indice_lambda])),
    mutate(filas, modelo = "gam", pred = exp(as.numeric(predict(f_gam, newdata = p$nuevos)))),
    mutate(filas, modelo = "bosque", pred = exp(predict(f_bosque, data = p$nuevos)$predictions))
  )
  list(pred = pred, lasso = f_lasso, gam = f_gam, bosque = f_bosque, columnas = colnames(x_entren))
}

# -----------------------------------------------------------------------------
# 2. Incertidumbre de la diferencia de MAE frente a la referencia
# -----------------------------------------------------------------------------
# Se remuestrean edificios con reposición (un edificio aparece en 2023 y en 2024, así
# que sus dos filas salen juntas). Las predicciones quedan fijas: el intervalo describe
# la incertidumbre por los edificios evaluados, condicional a los ajustes; no incluye
# la de selección y entrenamiento ni la de otros años (enunciado 4.3).
remuestreo_edificios <- function(pred, modelo_a, modelo_b = "referencia", B = B_BOOT,
                                 semilla = 3407) {
  a <- filter(pred, modelo == modelo_a) |> select(osebuildingid, datayear, y, pred_a = pred)
  b <- filter(pred, modelo == modelo_b) |> select(osebuildingid, datayear, pred_b = pred)
  d <- inner_join(a, b, by = c("osebuildingid", "datayear"))
  stopifnot(nrow(d) == nrow(a), nrow(d) == nrow(b))  # mismas filas para ambos
  por_edificio <- d |>
    group_by(osebuildingid) |>
    summarise(s = sum(abs(y - pred_a) - abs(y - pred_b)), n = n(), .groups = "drop")
  set.seed(semilla)
  m <- nrow(por_edificio)
  idx <- matrix(sample.int(m, m * B, replace = TRUE), nrow = m)
  t_boot <- colSums(matrix(por_edificio$s[idx], nrow = m)) /
    colSums(matrix(por_edificio$n[idx], nrow = m))
  data.frame(modelo = modelo_a, filas = nrow(d), edificios = m,
             dif_MAE = sum(por_edificio$s) / sum(por_edificio$n),
             ee_boot = sd(t_boot),
             li_95 = unname(quantile(t_boot, 0.025)),
             ls_95 = unname(quantile(t_boot, 0.975)),
             prop_boot_menor_0 = mean(t_boot < 0))
}

# Tabla de métricas por procedimiento, por año y reunida, con la diferencia frente a
# la referencia sobre las mismas filas.
tabla_metricas <- function(pred) {
  ref <- filter(pred, modelo == "referencia") |>
    select(osebuildingid, datayear, pred_ref = pred)
  con_ref <- left_join(pred, ref, by = c("osebuildingid", "datayear"))
  resumen <- function(x) {
    summarise(x, n = n(), edificios = n_distinct(osebuildingid),
              MAE = mean(abs(y - pred)), RMSE = sqrt(mean((y - pred)^2)),
              dif_MAE_vs_ref = MAE - mean(abs(y - pred_ref)), .groups = "drop")
  }
  bind_rows(
    con_ref |> group_by(modelo, anio = as.character(datayear)) |> resumen(),
    con_ref |> group_by(modelo) |> resumen() |> mutate(anio = "reunidos")
  ) |>
    arrange(anio, MAE)
}

# -----------------------------------------------------------------------------
# 3. Evaluación: métricas, incertidumbre y coeficientes del lasso final
# -----------------------------------------------------------------------------
evaluar <- function(entren, nuevos, elegido = procedimiento_elegido$modelo) {
  f <- predecir_todos(entren, nuevos)
  modelos <- c("lasso", "gam", "bosque")
  incertidumbre <- bind_rows(lapply(c("reunidos", sort(unique(nuevos$datayear))), function(a) {
    pr <- if (a == "reunidos") f$pred else filter(f$pred, datayear == as.numeric(a))
    bind_rows(
      lapply(modelos, function(m) mutate(remuestreo_edificios(pr, m), frente_a = "referencia")),
      mutate(remuestreo_edificios(pr, elegido, "referencia_ultima"), frente_a = "referencia_ultima")
    ) |> mutate(anio = a, elegido = modelo == elegido)
  }))
  b <- coef(f$lasso, s = grilla_lambda[indice_lambda])
  coeficientes <- data.frame(variable = rownames(b), coeficiente = as.numeric(b[, 1])) |>
    filter(coeficiente != 0)
  list(pred = f$pred, metricas = tabla_metricas(f$pred),
       por_historia = f$pred |> group_by(modelo, historia) |> resumir(),
       incertidumbre = incertidumbre, coeficientes = coeficientes)
}

# Filas de prueba: mismas reglas que en desarrollo (respuesta presente y sin error de
# registro). 2023 usa historia hasta 2021; 2024, hasta 2022.
prueba <- objetivos |>
  filter(rol == "prueba") |>
  mutate(historia = case_when(!is.na(eui_a2) ~ "EUI en a-2",
                              !sin_historia ~ "Solo historia anterior",
                              TRUE ~ "Sin historia"))
anios_prueba <- filter(datos, datayear %in% c(2023, 2024))
cascada_prueba <- data.frame(
  paso = c("Objetivos de prueba 2023-2024", "Con respuesta", "Sin errores de registro"),
  filas = c(nrow(anios_prueba), sum(!is.na(anios_prueba$eui)),
            sum(!is.na(anios_prueba$eui_valida))),
  edificios = c(n_distinct(anios_prueba$osebuildingid),
                n_distinct(anios_prueba$osebuildingid[!is.na(anios_prueba$eui)]),
                n_distinct(anios_prueba$osebuildingid[!is.na(anios_prueba$eui_valida)]))
)
stopifnot(nrow(prueba) == cascada_prueba$filas[3])
guardar(cascada_prueba, "cascada_prueba.csv")
pares_prueba <- as.data.frame.matrix(table(prueba$datayear, prueba$historia))
write.csv(pares_prueba, file.path(SALIDA, "pares_historia_prueba.csv"))

# Ajuste final con los objetivos 2017-2021 y evaluación única en 2023-2024.
res_prueba <- evaluar(dev, prueba)
guardar(res_prueba$pred, "predicciones_prueba.csv")
guardar(res_prueba$metricas, "metricas_prueba.csv")
guardar(res_prueba$por_historia, "metricas_prueba_por_historia.csv")
guardar(res_prueba$incertidumbre, "incertidumbre_prueba.csv")
guardar(res_prueba$coeficientes, "lasso_final_coeficientes.csv")

# Misma medida de incertidumbre en desarrollo, con las predicciones de la sección 2.
incertidumbre_desarrollo <- bind_rows(lapply(c("lasso", "gam", "bosque"), function(m)
  remuestreo_edificios(select(pred_elegidos, modelo, osebuildingid, datayear, y, pred), m)))
guardar(incertidumbre_desarrollo, "incertidumbre_desarrollo.csv")
