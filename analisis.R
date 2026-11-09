# =============================================================================
# EYP3407 · Caso 04 · Intensidad energética de edificios de Seattle
# analisis.R · Punto de entrada único
#
# Integrantes: Juan Pablo Cuevas, Cristóbal Honorato, Michelle Houngbo, Maximiliano León
#
# Uso, desde la raíz del repositorio y con los datos descomprimidos en datos/:
#   Rscript --vanilla analisis.R
# Requiere R >= 4.1 y los paquetes dplyr (>= 1.1.0), glmnet, mgcv, ranger, rmarkdown
# y knitr; para el informe, pandoc >= 2.0 y LaTeX (ver README.md).
# Todas las tablas y figuras quedan en resultados/, y el informe en informe.pdf.
# =============================================================================

t_inicio <- proc.time()[["elapsed"]]

# Requisitos: se comprueban al inicio para no detenerse a mitad del análisis. Los
# paquetes del análisis se buscan sin cargarlos, y todo ocurre antes de fijar la semilla.
paquetes <- c("dplyr", "glmnet", "mgcv", "ranger", "rmarkdown", "knitr")
faltan <- paquetes[!nzchar(vapply(paquetes, function(p) system.file(package = p), ""))]
if (length(faltan) > 0) {
  stop("Faltan paquetes de R: ", paste(faltan, collapse = ", "), ". Instálelos con install.packages(c(",
       paste0("\"", faltan, "\"", collapse = ", "), ")).")
}
if (utils::packageVersion("dplyr") < "1.1.0") stop("Se requiere dplyr >= 1.1.0.")
if (!rmarkdown::pandoc_available("2.0")) {
  stop("El informe requiere pandoc >= 2.0, que incluyen RStudio y Quarto. Instálelo o indique ",
       "su carpeta en la variable de entorno RSTUDIO_PANDOC (ver README.md).")
}

set.seed(3407)
options(width = 140)

# Orden alfabético y texto independientes del idioma del equipo: el orden de las
# categorías fija la categoría base del lasso, y las figuras llevan tildes.
invisible(Sys.setlocale("LC_COLLATE", "C"))
if (!isTRUE(l10n_info()[["UTF-8"]])) {
  for (loc in c("C.UTF-8", "en_US.UTF-8", "es_CL.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
}

source("R/01_base.R")   # Sección 1: base analítica, ventanas y referencia

# Resumen en consola de la sección 1
print(resumen_respuesta, row.names = FALSE, digits = 4)
print(auditoria_general)
print(auditoria_atributos, row.names = FALSE)
print(faltantes_por_anio)
print(cascada, row.names = FALSE)
print(pares)
print(altas_bajas, row.names = FALSE)
print(saltos_desarrollo, row.names = FALSE)
print(extremos, row.names = FALSE)
print(as.data.frame(metricas))
print(as.data.frame(por_historia))

source("R/02_modelos.R") # Sección 2: lasso, GAM y bosque en las tres ventanas

# Resumen en consola de la sección 2
print(as.data.frame(elegidos))
print(as.data.frame(comparacion), digits = 4)
print(as.data.frame(costo))
print(as.data.frame(dif_por_ventana), digits = 4)
print(as.data.frame(procedimiento_elegido), digits = 4)
print(as.data.frame(residuos_log), digits = 3)
print(as.data.frame(residuos_por_ventana), digits = 3)
print(as.data.frame(residuo_entren_elegidos), digits = 3)
print(as.data.frame(cambio_anual), digits = 3)
print(as.data.frame(por_historia_modelos), digits = 4)
print(as.data.frame(dispersion), digits = 3)
print(gam_k, digits = 3)
print(gam_concurvidad, digits = 3)
print(table(lasso_variables$ventana))

source("R/03_prueba.R")   # Sección 3: ajuste final y prueba 2023-2024, una sola vez

# Resumen en consola de la sección 3
print(cascada_prueba, row.names = FALSE)
print(pares_prueba)
print(as.data.frame(res_prueba$metricas), digits = 4)
print(as.data.frame(res_prueba$por_historia), digits = 4)
print(res_prueba$incertidumbre, digits = 3)
print(incertidumbre_desarrollo, digits = 3)
print(res_prueba$coeficientes, digits = 3)

source("R/04_diagnostico.R")  # Sección 4: diagnóstico, sensibilidades y figuras

# Resumen en consola de la sección 4
print(diag_tipo, digits = 4)
print(diag_uso, digits = 4)
print(diag_tamano, digits = 4)
print(diag_historia, digits = 4)
print(diag_extremos, digits = 4)
print(as.data.frame(sesgo_extremos), digits = 4)
print(mayores_errores, digits = 4)
print(as.data.frame(concentracion), digits = 3)
print(as.data.frame(error_entidad), digits = 4)
print(as.data.frame(cambio_por_anio), digits = 3)
print(cambio_por_tipo, digits = 3)
print(mae_por_anio, digits = 4)
print(as.data.frame(s1_comparacion), digits = 4)
print(as.data.frame(s2_comparacion), digits = 4)
print(as.data.frame(control_regla), digits = 4)

writeLines(capture.output(sessionInfo()), file.path(SALIDA, "sessionInfo.txt"))

source("R/05_informe.R")  # Sección 5: diagramas de la muestra y del diseño, auditoría e informe

cat(sprintf("Análisis e informe completos en %.1f minutos.\n", (proc.time()[["elapsed"]] - t_inicio) / 60))
