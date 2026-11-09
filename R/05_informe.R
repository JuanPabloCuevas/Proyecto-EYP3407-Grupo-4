# =============================================================================
# R/05_informe.R · Sección 5: diagramas del diseño, auditorías de la base e informe
# No ajusta modelos ni cambia resultados. Dibuja los diagramas de la muestra y del
# diseño temporal, resume la auditoría de columnas, superficies, identificadores,
# uniones y categorías, y genera el informe a partir de informe.Rmd, que lee sus
# cifras de resultados/.
# analisis.R lo ejecuta al final. También puede correrse solo, después de un análisis
# completo, para regenerar el informe sin reajustar modelos:
#   Rscript --vanilla R/05_informe.R
# =============================================================================

# Mismo idioma que analisis.R, por si este archivo se ejecuta solo: el informe compara
# textos con tildes y necesita UTF-8. Dentro de analisis.R no cambia nada.
invisible(Sys.setlocale("LC_COLLATE", "C"))
if (!isTRUE(l10n_info()[["UTF-8"]])) {
  for (loc in c("C.UTF-8", "en_US.UTF-8", "es_CL.UTF-8")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)))) break
  }
}

if (!exists("SALIDA")) SALIDA <- "resultados"
if (!exists("guardar")) {
  guardar <- function(tabla, nombre, ...) {
    write.csv(tabla, file.path(SALIDA, nombre), row.names = FALSE, ...)
  }
}
leer_resultado <- function(nombre) {
  read.csv(file.path(SALIDA, nombre), check.names = FALSE, stringsAsFactors = FALSE)
}
separar_miles <- function(x) {
  formatC(x, format = "d", big.mark = if (max(abs(x)) >= 10000) " " else "")
}

# -----------------------------------------------------------------------------
# 1. Auditoría de todas las columnas en 2015-2022: edificios en que el valor cambia
#    entre años y fracción de faltantes. Una columna que nunca cambia repite en todos
#    los años el valor actual del edificio.
# -----------------------------------------------------------------------------
crudo <- read.csv("datos/datos.csv", stringsAsFactors = FALSE, na.strings = c("", "NA"))
cuenta_crudo <- c(filas = nrow(crudo), edificios = length(unique(crudo$osebuildingid)))
crudo <- crudo[crudo$datayear <= 2022, ]
columnas_no_clave <- setdiff(names(crudo), c("osebuildingid", "datayear"))
auditoria_columnas <- data.frame(
  columna = columnas_no_clave,
  edificios_con_cambios = vapply(columnas_no_clave, function(col) {
    sum(tapply(crudo[[col]], crudo$osebuildingid, function(x) length(unique(x))) > 1)
  }, numeric(1)),
  fraccion_faltante = vapply(columnas_no_clave, function(col) mean(is.na(crudo[[col]])),
                             numeric(1)),
  row.names = NULL
)
guardar(auditoria_columnas, "auditoria_columnas.csv")

# -----------------------------------------------------------------------------
# 1b. Cobertura geográfica, identificadores y superficies en 2015-2022. Solo describe
#     los datos: ninguna de estas cifras entra a los modelos.
# -----------------------------------------------------------------------------
# Estas columnas repiten en todos los años el valor actual (sección 1), así que una fila
# por edificio las describe por completo.
copiadas <- c("address", "buildingname", "neighborhood", "zipcode", "city", "propertygfatotal",
              "propertygfabuildings", "propertygfaparking", "selfreportgfatotal")
stopifnot(all(auditoria_columnas$edificios_con_cambios[auditoria_columnas$columna %in% copiadas] == 0))
por_edificio <- crudo[!duplicated(crudo$osebuildingid), ]
normalizar <- function(x) toupper(trimws(x))
repetidos <- function(x) {
  k <- table(x)
  c(valores = sum(k > 1), edificios = sum(k[k > 1]))
}
edificios_barrio <- table(por_edificio$neighborhood)
dir_rep <- repetidos(normalizar(por_edificio$address))
nom_rep <- repetidos(normalizar(por_edificio$buildingname))
par_rep <- repetidos(paste(normalizar(por_edificio$address), normalizar(por_edificio$buildingname)))
razon_autodeclarada <- por_edificio$selfreportgfatotal / por_edificio$propertygfatotal
auditoria_complementaria <- data.frame(
  indicador = c(
    "Filas 2015-2022", "Edificios 2015-2022",
    "Ciudades distintas (sin distinguir mayúsculas)", "Barrios", "Edificios por barrio, mínimo",
    "Edificios por barrio, máximo", "Códigos postales",
    "Direcciones de más de un edificio", "Edificios con dirección compartida",
    "Nombres de más de un edificio", "Edificios con nombre compartido",
    "Pares dirección y nombre de más de un edificio",
    "Superficie confirmada mínima (pie2)",
    "Filas con superficie confirmada distinta de edificios más estacionamiento",
    "Filas con estacionamiento negativo", "Edificios con estacionamiento negativo",
    "Estacionamiento mínimo (pie2)",
    "Filas con superficie autodeclarada 0", "Edificios con superficie autodeclarada 0",
    "Edificios con superficie autodeclarada a más de 10 % de la confirmada",
    "Filas con superficie del uso principal mayor que 1,1 veces la de los edificios",
    "Filas sin superficie del uso principal"),
  valor = c(
    nrow(crudo), nrow(por_edificio),
    length(unique(normalizar(crudo$city))), length(edificios_barrio), min(edificios_barrio),
    max(edificios_barrio), length(unique(crudo$zipcode)),
    dir_rep[["valores"]], dir_rep[["edificios"]], nom_rep[["valores"]], nom_rep[["edificios"]],
    par_rep[["valores"]],
    min(crudo$propertygfatotal),
    sum(abs(crudo$propertygfatotal - crudo$propertygfabuildings - crudo$propertygfaparking) > 0.5),
    sum(crudo$propertygfaparking < 0),
    length(unique(crudo$osebuildingid[crudo$propertygfaparking < 0])),
    min(crudo$propertygfaparking),
    sum(crudo$selfreportgfatotal == 0), sum(por_edificio$selfreportgfatotal == 0),
    sum(abs(razon_autodeclarada - 1) > 0.10),
    sum(crudo$largestpropertyusetypegfa > 1.1 * crudo$propertygfabuildings, na.rm = TRUE),
    sum(is.na(crudo$largestpropertyusetypegfa)))
)
guardar(auditoria_complementaria, "auditoria_complementaria.csv")
rm(crudo, por_edificio)

# -----------------------------------------------------------------------------
# 1c. Uniones de la base y categorías poco frecuentes. Repite cada unión de R/01_base.R
#     y cuenta filas y edificios antes y después, y las filas que comparten un registro de
#     la derecha; esas tablas deben tener clave única. Usa los objetos de las secciones 1
#     a 3, así que solo corre dentro de analisis.R; si este archivo se ejecuta solo, se
#     conservan los de la corrida completa.
# -----------------------------------------------------------------------------
if (all(vapply(c("datos", "eui_a2", "eui_a3", "ultima", "usos", "dev", "prueba", "MIN_NIVEL"),
               exists, logical(1)))) {
  cuenta <- function(x) c(filas = nrow(x), edificios = length(unique(x$osebuildingid)))
  clave_unica <- function(x, claves) anyDuplicated(as.data.frame(x)[, claves]) == 0
  # Filas de la izquierda cuyo registro de la derecha también lo recibe otra fila: 0 en una
  # unión de uno a uno. Recibe la clave del registro unido a cada fila (NA si no hubo).
  compartidas <- function(clave) {
    clave <- as.data.frame(clave)
    clave <- clave[stats::complete.cases(clave), , drop = FALSE]
    k <- table(do.call(paste, c(unname(as.list(clave)), sep = "|")))
    sum(k[k > 1])
  }
  paso_union <- function(union, relacion, antes, despues, unica, compartidas) {
    data.frame(union = union, relacion = relacion, filas_antes = antes[["filas"]],
               filas_despues = despues[["filas"]], edificios_antes = antes[["edificios"]],
               edificios_despues = despues[["edificios"]], clave_derecha_unica = unica,
               filas_con_registro_compartido = compartidas)
  }
  obj0 <- datos |>
    filter(datayear %in% c(2017:2021, 2023:2024)) |>
    mutate(limite = datayear - 2)
  obj1 <- left_join(obj0, eui_a2, by = c("osebuildingid", "datayear"))
  obj2 <- left_join(obj1, eui_a3, by = c("osebuildingid", "datayear"))
  obj3 <- left_join(obj2, ultima, by = join_by(osebuildingid, closest(limite >= anio_h))) |>
    rename(anio_ultima = anio_h)
  obj4 <- left_join(obj3, usos, by = join_by(osebuildingid, closest(limite >= anio_h))) |>
    rename(anio_uso = anio_h)
  med_tipo_final <- dev |> group_by(buildingtype) |> summarise(med_tipo = median(eui), .groups = "drop")
  # La marca de error se calcula con las filas que tienen EUI, a lo más una por edificio y año.
  marcas_unicas <- datos |> filter(!is.na(eui)) |> select(osebuildingid, datayear)
  # Clave del registro de historia que recibe cada fila objetivo (NA si no lo hay).
  registro_a <- function(x, k, valor) {
    data.frame(osebuildingid = x$osebuildingid, anio = ifelse(is.na(x[[valor]]), NA, x$datayear - k))
  }
  uniones <- rbind(
    paso_union("Marca de error de registro a los registros 2015-2024",
               "uno a uno por edificio y año", cuenta_crudo, cuenta(datos),
               clave_unica(marcas_unicas, c("osebuildingid", "datayear")),
               compartidas(select(datos, osebuildingid, datayear))),
    paso_union("EUI de a-2 a las filas objetivo", "uno a uno por edificio y año",
               cuenta(obj0), cuenta(obj1), clave_unica(eui_a2, c("osebuildingid", "datayear")),
               compartidas(registro_a(obj1, 2, "eui_a2"))),
    paso_union("EUI de a-3 a las filas objetivo", "uno a uno por edificio y año",
               cuenta(obj1), cuenta(obj2), clave_unica(eui_a3, c("osebuildingid", "datayear")),
               compartidas(registro_a(obj2, 3, "eui_a3"))),
    paso_union("Última EUI válida hasta a-2", "muchos a uno: registro válido más reciente <= a-2 del edificio",
               cuenta(obj2), cuenta(obj3), clave_unica(ultima, c("osebuildingid", "anio_h")),
               compartidas(select(obj3, osebuildingid, anio_ultima))),
    paso_union("Uso del último registro hasta a-2", "muchos a uno: registro más reciente <= a-2 del edificio",
               cuenta(obj3), cuenta(obj4), clave_unica(usos, c("osebuildingid", "anio_h")),
               compartidas(select(obj4, osebuildingid, anio_uso))),
    paso_union("Mediana por tipo del entrenamiento final a las filas de prueba (referencia)",
               "muchos a uno por tipo", cuenta(prueba),
               cuenta(left_join(prueba, med_tipo_final, by = "buildingtype")),
               clave_unica(med_tipo_final, "buildingtype"), compartidas(select(prueba, buildingtype))))
  guardar(uniones, "uniones.csv")

  # Categorías del entrenamiento final (objetivos 2017-2021) que el preprocesamiento
  # agrupa: menos de MIN_NIVEL filas pasan a "Otro" y un valor ausente, a "Sin dato".
  categorias_entrenamiento <- do.call(rbind, lapply(c("uso_prev", "buildingtype", "neighborhood"), function(v) {
    k <- table(dev[[v]])
    data.frame(variable = v, filas = nrow(dev), categorias = length(k),
               categorias_a_otro = sum(k < MIN_NIVEL), filas_a_otro = sum(k[k < MIN_NIVEL]),
               filas_sin_dato = sum(is.na(dev[[v]])))
  }))
  guardar(categorias_entrenamiento, "categorias_entrenamiento_final.csv")
} else {
  message("Uniones y categorías: se conservan los archivos de la última corrida completa.")
}

# -----------------------------------------------------------------------------
# 2. Figura 1: construcción de la muestra (cifras leídas de resultados/)
# -----------------------------------------------------------------------------
cas_d <- leer_resultado("cascada.csv")
cas_p <- leer_resultado("cascada_prueba.csv")
par_d <- leer_resultado("pares_historia.csv")
par_p <- leer_resultado("pares_historia_prueba.csv")
inc_d <- leer_resultado("incertidumbre_desarrollo.csv")
ab <- leer_resultado("altas_bajas.csv")
falt <- leer_resultado("faltantes_por_anio.csv")
validacion <- par_d[par_d[[1]] %in% 2019:2021, ]
solo_historia <- sum(falt$filas[falt$anio %in% c(2015, 2016, 2022)])

caja <- function(x, y, texto, ancho, alto, fondo = "#f3f3f1", borde = "#8a8a85", lty = 1,
                 cex = 0.78, font = 1) {
  rect(x - ancho / 2, y - alto / 2, x + ancho / 2, y + alto / 2, col = fondo, border = borde,
       lty = lty)
  text(x, y, texto, cex = cex, font = font, col = "#1f1f1f")
}
flecha <- function(x0, y0, x1, y1) arrows(x0, y0, x1, y1, length = 0.05, col = "#6b6b66")
nota <- function(x, y, texto) text(x, y, texto, cex = 0.7, col = "#6b6b66", adj = 0, font = 3)
fila_paso <- function(cas, paso) cas[cas$paso == paso, ]

png(file.path(SALIDA, "fig1_construccion_muestra.png"), width = 6.5, height = 3.9, units = "in",
    res = 300, pointsize = 10)
par(mar = c(0.2, 0.2, 0.2, 0.2))
plot(NA, xlim = c(0, 10), ylim = c(0, 10.4), axes = FALSE, xlab = "", ylab = "")
total <- fila_paso(cas_d, "Registros 2015-2024")
caja(5, 9.75, sprintf(paste0("Paquete del caso, 2015\u20132024: %s filas edificio\u2013año, ",
                             "%s edificios\n2015, 2016 y 2022 solo sirven como historia (%s filas)"),
                      separar_miles(total$filas), separar_miles(total$edificios),
                      separar_miles(solo_historia)),
     ancho = 9.4, alto = 1.0, fondo = "#e6e6e3")
columnas_fig <- list(
  list(x = 2.5, cas = cas_d, titulo = "Desarrollo: objetivos 2017\u20132021",
       paso1 = "Objetivos de desarrollo 2017-2021",
       evaluadas = sprintf("Validación 2019\u20132021\n%s filas, %s edificios",
                           separar_miles(sum(validacion[, -1])), separar_miles(inc_d$edificios[1])),
       pares = validacion),
  list(x = 7.5, cas = cas_p, titulo = "Prueba: objetivos 2023\u20132024",
       paso1 = "Objetivos de prueba 2023-2024",
       evaluadas = sprintf("Prueba 2023\u20132024\n%s filas, %s edificios",
                           separar_miles(cas_p$filas[3]), separar_miles(cas_p$edificios[3])),
       pares = par_p)
)
for (cf in columnas_fig) {
  pasos <- cf$cas$filas
  edif <- cf$cas$edificios
  i0 <- which(cf$cas$paso == cf$paso1)
  flecha(5 + sign(cf$x - 5) * 1.0, 9.25, cf$x, 8.55)
  caja(cf$x, 8.1, sprintf("%s\n%s filas, %s edificios", cf$titulo, separar_miles(pasos[i0]),
                          separar_miles(edif[i0])), ancho = 3.6, alto = 0.9)
  flecha(cf$x, 7.65, cf$x, 6.75)
  nota(cf$x + 0.1, 7.2, sprintf("\u2212%s sin EUI del año",
                                separar_miles(pasos[i0] - pasos[i0 + 1])))
  caja(cf$x, 6.3, sprintf("Con respuesta\n%s filas, %s edificios", separar_miles(pasos[i0 + 1]),
                          separar_miles(edif[i0 + 1])), ancho = 3.6, alto = 0.9)
  flecha(cf$x, 5.85, cf$x, 4.95)
  nota(cf$x + 0.1, 5.4, sprintf("\u2212%d errores de registro", pasos[i0 + 1] - pasos[i0 + 2]))
  caja(cf$x, 4.5, sprintf("Sin errores de registro\n%s filas, %s edificios",
                          separar_miles(pasos[i0 + 2]), separar_miles(edif[i0 + 2])),
       ancho = 3.6, alto = 0.9, fondo = "#dce9f7")
  flecha(cf$x, 4.05, cf$x, 3.25)
  caja(cf$x, 2.8, cf$evaluadas, ancho = 3.9, alto = 0.9, fondo = "#fbe3d6")
  k <- colSums(cf$pares[, c("EUI en a-2", "Solo historia anterior", "Sin historia")])
  xs <- cf$x + c(-1.3, 0, 1.3)
  for (j in 1:3) {
    flecha(cf$x, 2.35, xs[j], 1.55)
    caja(xs[j], 1.0, sprintf("%s\n%s", c("EUI en a\u22122", "Solo historia\nanterior", "Sin historia")[j],
                             separar_miles(k[j])), ancho = 1.25, alto = 1.1, cex = 0.7)
  }
}
dev.off()

# -----------------------------------------------------------------------------
# 3. Figura 2: diseño temporal de las ventanas de desarrollo y de la prueba
# -----------------------------------------------------------------------------
filas_diseno <- list(
  list(nombre = "Ventana 1", objetivo = 2019, entrena = 2017, rol = "V"),
  list(nombre = "Ventana 2", objetivo = 2020, entrena = 2017:2018, rol = "V"),
  list(nombre = "Ventana 3", objetivo = 2021, entrena = 2017:2019, rol = "V"),
  list(nombre = "Final: prueba 2023", objetivo = 2023, entrena = 2017:2021, rol = "P"),
  list(nombre = "Final: prueba 2024", objetivo = 2024, entrena = 2017:2021, rol = "P")
)
colores_rol <- c(E = "#2a78d6", V = "#eb6834", P = "#eb6834", H = "#d9d9d6", N = "#ffffff")
etiquetas_rol <- c(E = "E", V = "V", P = "P", H = "H", N = "")
png(file.path(SALIDA, "fig2_diseno_temporal.png"), width = 6.5, height = 3.1, units = "in",
    res = 300, pointsize = 10)
par(mar = c(4.2, 9.2, 0.4, 0.6), las = 1)
anios_d <- 2015:2024
plot(NA, xlim = c(2014.5, 2024.5), ylim = c(0.4, length(filas_diseno) + 0.6), axes = FALSE,
     xlab = "", ylab = "")
for (i in seq_along(filas_diseno)) {
  f <- filas_diseno[[i]]
  y <- length(filas_diseno) + 1 - i
  for (a in anios_d) {
    rol <- if (a == f$objetivo) f$rol else if (a %in% f$entrena) "E" else
      if (a <= f$objetivo - 2) "H" else "N"
    borde <- if (rol == "N") "#c4c4c0" else "#ffffff"
    rect(a - 0.46, y - 0.38, a + 0.46, y + 0.38, col = colores_rol[[rol]], border = borde)
    if (a == f$objetivo - 1) text(a, y, "a\u22121", cex = 0.7, col = "#8a8a85")
    if (rol %in% c("E", "V", "P")) text(a, y, etiquetas_rol[[rol]], cex = 0.75, col = "#ffffff",
                                         font = 2)
    if (rol == "H") text(a, y, "H", cex = 0.75, col = "#6b6b66", font = 2)
  }
  mtext(f$nombre, side = 2, at = y, line = 0.4, cex = 0.8, col = "#1f1f1f")
}
abline(h = 2.5, lty = 2, col = "#8a8a85")
axis(1, at = anios_d, tick = FALSE, line = -0.9, cex.axis = 0.8, col.axis = "#3d3d3a")
legend(x = 2019.5, y = -0.2, xjust = 0.5, yjust = 1, xpd = NA, ncol = 2, bty = "n", cex = 0.75,
       fill = c(colores_rol[["E"]], colores_rol[["H"]], colores_rol[["V"]], "#ffffff"),
       border = c("#ffffff", "#ffffff", "#ffffff", "#c4c4c0"),
       legend = c("E: objetivo de entrenamiento", "H: solo historia",
                  "V / P: año evaluado (validación o prueba)",
                  "Sin uso: a \u2212 1 (reporte incompleto) o posterior"),
       text.col = "#3d3d3a")
dev.off()

# -----------------------------------------------------------------------------
# 4. Tiempo de ejecución y entorno (solo en una corrida completa desde analisis.R)
# -----------------------------------------------------------------------------
if (exists("t_inicio")) {
  guardar(data.frame(
    segundos_analisis = round(proc.time()[["elapsed"]] - t_inicio),
    nucleos = parallel::detectCores(),
    sistema = utils::sessionInfo()$running,
    r = R.version.string
  ), "tiempo_ejecucion.csv")
}

# -----------------------------------------------------------------------------
# 5. Informe: PDF con LaTeX; si no hay LaTeX, HTML con aviso
# -----------------------------------------------------------------------------
generar_informe <- function() {
  if (!requireNamespace("rmarkdown", quietly = TRUE) || !requireNamespace("knitr", quietly = TRUE)) {
    warning("No se generó el informe: faltan los paquetes rmarkdown y knitr (ver README.md).")
    return(invisible(NULL))
  }
  if (!rmarkdown::pandoc_available("2.0")) {
    warning("No se generó el informe: falta pandoc >= 2.0 (viene con RStudio y Quarto; ver README.md).")
    return(invisible(NULL))
  }
  hay_latex <- nzchar(Sys.which("pdflatex")) ||
    (requireNamespace("tinytex", quietly = TRUE) && tinytex::is_tinytex())
  if (hay_latex) {
    salida <- tryCatch(
      rmarkdown::render("informe.Rmd", output_format = "pdf_document", envir = new.env(),
                        quiet = TRUE),
      error = function(e) {
        message("No se pudo compilar el PDF: ", conditionMessage(e))
        NULL
      })
    if (!is.null(salida)) {
      cat("Informe generado:", salida, "\n")
      return(invisible(salida))
    }
    warning("No se pudo generar el PDF (ver el mensaje anterior); se intenta en HTML.")
  } else {
    warning("No se encontró LaTeX, así que el informe se genera en HTML. ",
            "Para el PDF instale LaTeX, por ejemplo con tinytex::install_tinytex().")
  }
  salida <- rmarkdown::render("informe.Rmd", output_format = "html_document", envir = new.env(),
                              quiet = TRUE)
  cat("Informe generado:", salida, "\n")
  invisible(salida)
}
generar_informe()
