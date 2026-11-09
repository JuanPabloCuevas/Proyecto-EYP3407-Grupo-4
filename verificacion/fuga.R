# =============================================================================
# EYP3407 · Caso 04 · verificacion/fuga.R
# Prueba de fuga de información. analisis.R no la ejecuta.
#
# Uso, desde la raíz del repositorio y después de correr analisis.R:
#   Rscript --vanilla verificacion/fuga.R
# Tarda unos 15 minutos. No modifica resultados/: cada corrida escribe en una carpeta
# temporal, y el resumen queda en verificacion/resultado_fuga.txt.
#
# Idea: para un corte c se alteran al azar la EUI y las columnas de uso de todos los
# años posteriores a c, y se repite el análisis con el mismo código (R/01 a R/03).
# Si las predicciones del año c + 2 usan solo información de años <= c, incluidas las
# etiquetas de entrenamiento, deben quedar idénticas en las filas presentes en ambas
# corridas. Como control, las predicciones que sí usan años alterados deben cambiar.
#   - Desarrollo: cortes 2017, 2018 y 2019, que validan 2019, 2020 y 2021. Se comparan
#     las 35 configuraciones y la referencia con una corrida sin alterar.
#   - Prueba: cortes 2021 (2023 usa historia hasta 2021) y 2022 (2024 usa historia
#     hasta 2022). Se comparan los cinco procedimientos con resultados/predicciones_prueba.csv.
# =============================================================================

invisible(Sys.setlocale("LC_COLLATE", "C"))
if (!isTRUE(l10n_info()[["UTF-8"]])) {
  for (loc in c("C.UTF-8", "en_US.UTF-8", "es_CL.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
}
if (!all(file.exists(c("analisis.R", "datos/datos.csv", "resultados/predicciones_prueba.csv",
                       "resultados/predicciones_elegidas.csv")))) {
  stop("Ejecute este archivo desde la raíz del repositorio, después de correr analisis.R.")
}
suppressPackageStartupMessages(library(dplyr))
options(width = 150)
t0 <- proc.time()[["elapsed"]]

original <- utils::read.csv("datos/datos.csv", stringsAsFactors = FALSE, na.strings = c("", "NA"))
columnas_uso <- c("largestpropertyusetype", "largestpropertyusetypegfa",
                  "secondlargestpropertyusetype", "secondlargestpropertyuse",
                  "thirdlargestpropertyusetype", "thirdlargestpropertyusetypegfa")

# Permuta la EUI de los años > corte entre esas filas, la multiplica por un ruido
# lognormal y permuta las columnas de uso de esos mismos años.
alterar <- function(d, corte) {
  set.seed(99)
  fut <- d$datayear > corte
  d$siteeui_kbtu_sf[fut] <- sample(d$siteeui_kbtu_sf[fut]) * exp(rnorm(sum(fut), 0, 0.5))
  for (v in columnas_uso) d[[v]][fut] <- sample(d[[v]][fut])
  d
}

# Corre R/01, R/02 y, si se pide, R/03 en un entorno aparte, con datos.csv sustituido
# y las salidas en una carpeta temporal.
correr <- function(datos_entrada, etiqueta, con_prueba) {
  e <- new.env(parent = globalenv())
  e$SALIDA <- file.path(tempdir(), paste0("fuga_", etiqueta))
  e$read.csv <- function(file, ...) {
    if (basename(file) == "datos.csv") datos_entrada else utils::read.csv(file, ...)
  }
  archivos <- c("R/01_base.R", "R/02_modelos.R", if (con_prueba) "R/03_prueba.R")
  for (f in archivos) source(f, local = e)
  cat(sprintf("  corrida %-12s lista (%.1f min acumulados)\n", etiqueta,
              (proc.time()[["elapsed"]] - t0) / 60))
  list(salida = e$SALIDA, pred_modelos = e$pred_modelos, pred_dev = e$pred_dev,
       pred_prueba = if (con_prueba) {
         utils::read.csv(file.path(e$SALIDA, "predicciones_prueba.csv"), stringsAsFactors = FALSE)
       })
}

comparar <- function(a, b, claves) {
  j <- inner_join(a, b, by = claves, suffix = c("_a", "_b"))
  c(filas_comunes = nrow(j), max_dif = max(abs(j$pred_a - j$pred_b)),
    y_distinta = mean(j$y_a != j$y_b))
}

cat("Prueba de fuga\n")
base <- correr(original, "sin_alterar", con_prueba = FALSE)

# La corrida sin alterar debe reproducir byte a byte las predicciones de desarrollo
# que guardó analisis.R.
reproduce <- unname(tools::md5sum(file.path(base$salida, "predicciones_elegidas.csv")) ==
                      tools::md5sum("resultados/predicciones_elegidas.csv"))
n_config <- nrow(distinct(base$pred_modelos, modelo, config))

filas <- list()
for (corte in 2017:2019) {
  v <- corte + 2
  alt <- correr(alterar(original, corte), paste0("corte_", corte), con_prueba = FALSE)
  claves <- c("modelo", "config", "osebuildingid")
  m <- comparar(select(filter(base$pred_modelos, ventana == v), modelo, config, osebuildingid, pred, y),
                select(filter(alt$pred_modelos, ventana == v), modelo, config, osebuildingid, pred, y),
                claves)
  r <- comparar(select(filter(base$pred_dev, ventana == v), osebuildingid, pred, y),
                select(filter(alt$pred_dev, ventana == v), osebuildingid, pred, y), "osebuildingid")
  control <- if (v < 2021) {
    comparar(select(filter(base$pred_modelos, ventana == 2021), modelo, config, osebuildingid, pred, y),
             select(filter(alt$pred_modelos, ventana == 2021), modelo, config, osebuildingid, pred, y),
             claves)[["max_dif"]]
  } else NA
  stopifnot(m[["filas_comunes"]] == n_config * r[["filas_comunes"]])
  filas[[length(filas) + 1]] <- data.frame(
    parte = "desarrollo", corte = corte, anio_evaluado = v, filas_comunes = r[["filas_comunes"]],
    respuesta_alterada = round(m[["y_distinta"]], 3),
    max_dif_modelos = m[["max_dif"]], max_dif_referencia = r[["max_dif"]],
    control_2021_cambia = control)
}

original_prueba <- utils::read.csv("resultados/predicciones_prueba.csv", stringsAsFactors = FALSE)
for (corte in 2021:2022) {
  alt <- correr(alterar(original, corte), paste0("corte_", corte), con_prueba = TRUE)
  for (a in c(2023, 2024)) {
    k <- comparar(select(filter(original_prueba, datayear == a), modelo, osebuildingid, pred, y),
                  select(filter(alt$pred_prueba, datayear == a), modelo, osebuildingid, pred, y),
                  c("modelo", "osebuildingid"))
    filas[[length(filas) + 1]] <- data.frame(
      parte = "prueba", corte = corte, anio_evaluado = a,
      filas_comunes = k[["filas_comunes"]] / length(unique(original_prueba$modelo)),
      respuesta_alterada = round(k[["y_distinta"]], 3),
      max_dif_modelos = k[["max_dif"]], max_dif_referencia = NA, control_2021_cambia = NA)
  }
}
tabla <- bind_rows(filas)

# Debe usar solo años <= corte: desarrollo, y prueba con a - 2 <= corte.
debe_igual <- with(tabla, parte == "desarrollo" | anio_evaluado - 2 <= corte)
ok_igual <- with(tabla, debe_igual & max_dif_modelos == 0 & (is.na(max_dif_referencia) | max_dif_referencia == 0))
ok_control <- with(tabla, (!debe_igual & max_dif_modelos > 0) |
                     (debe_igual & (is.na(control_2021_cambia) | control_2021_cambia > 0)))
tabla$resultado <- ifelse(debe_igual, ifelse(ok_igual, "idénticas", "CAMBIAN: posible fuga"),
                          ifelse(tabla$max_dif_modelos > 0, "cambian (control esperado)",
                                 "NO cambian: la alteración no tuvo efecto"))

salida <- c(
  "Prueba de fuga de información (verificacion/fuga.R)",
  paste("Fecha:", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  paste("Entorno:", R.version.string, "en", utils::sessionInfo()$running),
  sprintf("Tiempo: %.1f minutos", (proc.time()[["elapsed"]] - t0) / 60),
  "",
  sprintf("La corrida sin alterar reproduce byte a byte resultados/predicciones_elegidas.csv: %s.",
          if (reproduce) "sí" else "NO"),
  sprintf("Configuraciones comparadas en desarrollo: %d, más la referencia.", n_config),
  "",
  "respuesta_alterada: fracción de filas comunes cuya EUI del año evaluado cambió con la alteración.",
  "max_dif_modelos: mayor diferencia absoluta entre predicciones (kBtu/pie²) en las filas comunes;",
  "  en desarrollo, sobre las 35 configuraciones; en prueba, sobre los cinco procedimientos.",
  "control_2021_cambia: en desarrollo, la mayor diferencia en la ventana 2021, que sí usa años alterados.",
  "",
  capture.output(print(tabla, row.names = FALSE)),
  "",
  if (all(ok_igual[debe_igual]) && all(ok_control) && reproduce) {
    "Conclusión: ninguna predicción que debía usar solo años <= corte cambió, y los controles sí cambiaron."
  } else {
    "Conclusión: la prueba NO se cumple; revisar las filas marcadas."
  })
writeLines(salida, "verificacion/resultado_fuga.txt", useBytes = TRUE)
cat(salida, sep = "\n")
