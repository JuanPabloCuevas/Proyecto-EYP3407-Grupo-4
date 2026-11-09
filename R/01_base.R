# =============================================================================
# R/01_base.R · Sección 1: base analítica, ventanas temporales y referencia
# Se ejecuta desde analisis.R, con el directorio de trabajo en la raíz del repositorio.
# =============================================================================

suppressPackageStartupMessages(library(dplyr))

# Parámetros (analisis.R puede fijarlos antes de llamar a este archivo).
if (!exists("APLICAR_REGLA")) APLICAR_REGLA <- TRUE  # regla de errores de registro
if (!exists("UMBRAL_SALTO")) UMBRAL_SALTO <- 10      # veces la mediana de años anteriores
if (!exists("UMBRAL_NIVEL")) UMBRAL_NIVEL <- 1000    # kBtu/pie²
if (!exists("SALIDA")) SALIDA <- "resultados"
dir.create(SALIDA, showWarnings = FALSE, recursive = TRUE)
guardar <- function(tabla, nombre, ...) {
  write.csv(tabla, file.path(SALIDA, nombre), row.names = FALSE, ...)
}

# -----------------------------------------------------------------------------
# 1. Lectura y auditoría
# -----------------------------------------------------------------------------
# na.strings: en el CSV los textos ausentes vienen vacíos; sin esto R los lee como "".
datos <- read.csv("datos/datos.csv", stringsAsFactors = FALSE, na.strings = c("", "NA")) |>
  rename(eui = siteeui_kbtu_sf)

# La clave edificio-año debe ser única.
stopifnot(anyDuplicated(datos[, c("osebuildingid", "datayear")]) == 0)

# La auditoría usa solo 2015-2022: la reserva 2023-2024 queda sellada.
desarrollo_anios <- filter(datos, datayear <= 2022)

# ¿Qué columnas cambian dentro de un mismo edificio? Las que nunca cambian son el
# valor actual copiado a todos los años; las que cambian se reportan cada año.
columnas_auditadas <- c(
  "buildingname", "address", "taxparcelidentificationnumber", "buildingtype",
  "yearbuilt", "numberoffloors", "numberofbuildings", "propertygfatotal",
  "propertygfabuildings", "propertygfaparking", "neighborhood", "zipcode",
  "latitude", "longitude", "councildistrictcode", "epapropertytype",
  "largestpropertyusetype", "largestpropertyusetypegfa",
  "secondlargestpropertyusetype", "secondlargestpropertyuse")
auditoria_atributos <- data.frame(
  columna = columnas_auditadas,
  edificios_con_cambios = sapply(columnas_auditadas, function(col) {
    distintos <- tapply(desarrollo_anios[[col]], desarrollo_anios$osebuildingid,
                        function(x) length(unique(x)))
    sum(distintos > 1)
  })
)
guardar(auditoria_atributos, "auditoria_atributos.csv")

parcelas <- desarrollo_anios |>
  distinct(taxparcelidentificationnumber, osebuildingid) |>
  count(taxparcelidentificationnumber, name = "edificios")
auditoria_general <- data.frame(
  indicador = c("Edificios 2015-2022", "Parcelas", "Parcelas con más de un edificio",
                "Filas con 0 pisos", "Filas con 0 edificios",
                "Filas con segundo uso sin su superficie",
                "Filas con tercer uso sin su superficie"),
  valor = c(n_distinct(desarrollo_anios$osebuildingid), nrow(parcelas),
            sum(parcelas$edificios > 1),
            sum(desarrollo_anios$numberoffloors == 0),
            sum(desarrollo_anios$numberofbuildings == 0),
            sum(!is.na(desarrollo_anios$secondlargestpropertyusetype) &
                  is.na(desarrollo_anios$secondlargestpropertyuse)),
            sum(!is.na(desarrollo_anios$thirdlargestpropertyusetype) &
                  is.na(desarrollo_anios$thirdlargestpropertyusetypegfa)))
)
guardar(auditoria_general, "auditoria_general.csv")

faltantes_por_anio <- desarrollo_anios |>
  group_by(anio = datayear) |>
  summarise(filas = n(), sin_respuesta = sum(is.na(eui)), .groups = "drop")
guardar(faltantes_por_anio, "faltantes_por_anio.csv")

# -----------------------------------------------------------------------------
# 2. Regla de errores de registro, fijada antes de ajustar modelos
# -----------------------------------------------------------------------------
# Un registro es error de registro si su EUI supera UMBRAL_SALTO veces la mediana
# de las EUI anteriores del mismo edificio y además supera UMBRAL_NIVEL, un nivel
# que en 2015-2022 solo sostiene un centro de datos, cuya historia ya era alta.
# Ese registro no sirve como objetivo ni como historia. La regla solo mira años
# anteriores, así que no usa información futura. La segunda condición evita marcar
# recuperaciones después de valores casi nulos. Las caídas no se marcan: un
# edificio puede vaciarse (por ejemplo, en 2020-2021).
mediana_anterior <- function(x) {
  sapply(seq_along(x), function(i) if (i == 1) NA_real_ else median(x[seq_len(i - 1)]))
}
marcas <- datos |>
  filter(!is.na(eui)) |>
  arrange(osebuildingid, datayear) |>
  group_by(osebuildingid) |>
  mutate(mediana_previa = mediana_anterior(eui)) |>
  ungroup() |>
  mutate(salto = !is.na(mediana_previa) & eui > UMBRAL_SALTO * mediana_previa,
         error_registro = salto & eui > UMBRAL_NIVEL) |>
  select(osebuildingid, datayear, mediana_previa, salto, error_registro)

datos <- datos |>
  left_join(marcas, by = c("osebuildingid", "datayear")) |>
  mutate(salto = coalesce(salto, FALSE), error_registro = coalesce(error_registro, FALSE))

saltos_desarrollo <- datos |>
  filter(salto, datayear <= 2022) |>
  transmute(osebuildingid, datayear, buildingtype, eui, mediana_previa,
            veces = eui / mediana_previa, error_registro) |>
  arrange(desc(veces))
errores_desarrollo <- filter(saltos_desarrollo, error_registro)
guardar(saltos_desarrollo, "saltos_2015_2022.csv")

if (APLICAR_REGLA) {
  datos <- mutate(datos, eui_valida = ifelse(error_registro, NA, eui))
} else {
  datos <- mutate(datos, eui_valida = eui)
}

# -----------------------------------------------------------------------------
# 3. Registros que pueden servir de historia
# -----------------------------------------------------------------------------
# Cada objetivo del año a solo mira registros de años <= a - 2, porque el
# reporte de a - 1 no está completo en enero de a (ficha del caso).
# El uso del edificio se reporta cada año, así que también se toma de la historia.
historia <- datos |>
  transmute(
    osebuildingid,
    anio_h = datayear,
    eui_h = eui_valida,
    uso_h = largestpropertyusetype,
    # Superficie del 2.º y 3.er uso: 0 si ese uso no existe (se decide por el tipo);
    # NA si el uso existe pero falta su superficie (faltante real).
    gfa1 = largestpropertyusetypegfa,
    gfa2 = ifelse(is.na(secondlargestpropertyusetype), 0, secondlargestpropertyuse),
    gfa3 = ifelse(is.na(thirdlargestpropertyusetype), 0, thirdlargestpropertyusetypegfa),
    frac_uso_h = gfa1 / (gfa1 + gfa2 + gfa3),
    n_usos_h = ifelse(is.na(uso_h), NA,
                      1 + !is.na(secondlargestpropertyusetype) +
                        !is.na(thirdlargestpropertyusetype))
  )
eui_historia <- filter(historia, !is.na(eui_h))

# -----------------------------------------------------------------------------
# 4. Filas objetivo: un edificio en un año a, con a en 2017-2021 (desarrollo)
#    o en 2023-2024 (prueba). 2022 solo sirve como historia para predecir 2024.
# -----------------------------------------------------------------------------
objetivos <- datos |>
  filter(datayear %in% c(2017:2021, 2023:2024)) |>
  mutate(rol = ifelse(datayear <= 2021, "desarrollo", "prueba"),
         limite = datayear - 2)

# EUI exactamente en a - 2 y en a - 3. Se une por año exacto: lag() por fila
# tomaría el año anterior que exista, que no siempre es a - 2.
eui_a2 <- transmute(eui_historia, osebuildingid, datayear = anio_h + 2, eui_a2 = eui_h)
eui_a3 <- transmute(eui_historia, osebuildingid, datayear = anio_h + 3, eui_a3 = eui_h)
objetivos <- objetivos |>
  left_join(eui_a2, by = c("osebuildingid", "datayear")) |>
  left_join(eui_a3, by = c("osebuildingid", "datayear"))

# Última EUI válida hasta a - 2 y cuántos años hace, para edificios que no
# reportaron justo en a - 2. closest() toma el año más reciente <= limite.
ultima <- transmute(eui_historia, osebuildingid, anio_h, ultima_eui = eui_h)
objetivos <- objetivos |>
  left_join(ultima, by = join_by(osebuildingid, closest(limite >= anio_h))) |>
  mutate(anios_desde_ultima = datayear - anio_h,
         sin_historia = is.na(ultima_eui)) |>
  select(-anio_h)

# Uso del edificio según su último registro hasta a - 2.
usos <- transmute(historia, osebuildingid, anio_h,
                  uso_prev = uso_h, frac_uso_prev = frac_uso_h, n_usos_prev = n_usos_h)
objetivos <- objetivos |>
  left_join(usos, by = join_by(osebuildingid, closest(limite >= anio_h))) |>
  rename(anio_uso_prev = anio_h)

# Comprobaciones: ninguna variable de historia viene de a - 1 o de años posteriores.
stopifnot(all(objetivos$anios_desde_ultima >= 2, na.rm = TRUE))
stopifnot(all(objetivos$anio_uso_prev <= objetivos$limite, na.rm = TRUE))
stopifnot(with(objetivos, all(is.na(eui_a2) | ultima_eui == eui_a2)))

# -----------------------------------------------------------------------------
# 5. Atributos copiados a todos los años (valor actual del edificio). Son
#    admisibles con el supuesto declarado de características estables.
# -----------------------------------------------------------------------------
objetivos <- objetivos |>
  mutate(antiguedad = datayear - yearbuilt,
         log_superficie = log(propertygfatotal),
         frac_estacionamiento = propertygfaparking / propertygfatotal)

# -----------------------------------------------------------------------------
# 6. Respuesta: salen las filas sin EUI del año a (no se imputan) y, si se aplica
#    la regla, las marcadas como error de registro.
# -----------------------------------------------------------------------------
cuenta_dev <- function(x) {
  c(filas = sum(x$rol == "desarrollo"),
    edificios = n_distinct(x$osebuildingid[x$rol == "desarrollo"]))
}
paso_total <- cuenta_dev(objetivos)
objetivos <- filter(objetivos, !is.na(eui))
paso_respuesta <- cuenta_dev(objetivos)
objetivos <- filter(objetivos, !is.na(eui_valida))
paso_regla <- cuenta_dev(objetivos)

dev <- objetivos |>
  filter(rol == "desarrollo") |>
  mutate(historia = case_when(!is.na(eui_a2) ~ "EUI en a-2",
                              !sin_historia ~ "Solo historia anterior",
                              TRUE ~ "Sin historia"))

# Tablas para la sección de datos del informe (solo desarrollo).
cascada <- data.frame(
  paso = c("Registros 2015-2024", "Objetivos de desarrollo 2017-2021",
           "Con respuesta", "Sin errores de registro"),
  filas = c(nrow(datos), paso_total["filas"], paso_respuesta["filas"], paso_regla["filas"]),
  edificios = c(n_distinct(datos$osebuildingid), paso_total["edificios"],
                paso_respuesta["edificios"], paso_regla["edificios"])
)
guardar(cascada, "cascada.csv")

pares <- as.data.frame.matrix(table(dev$datayear, dev$historia))
write.csv(pares, file.path(SALIDA, "pares_historia.csv"))

# Altas y bajas de edificios por año, con los años 2015-2022.
presencia <- split(desarrollo_anios$osebuildingid, desarrollo_anios$datayear)
anterior <- presencia[-length(presencia)]
actual <- presencia[-1]
altas_bajas <- data.frame(
  anio = as.integer(names(actual)),
  edificios = lengths(actual),
  altas = mapply(function(a, b) length(setdiff(b, a)), anterior, actual),
  bajas = mapply(function(a, b) length(setdiff(a, b)), anterior, actual)
)
guardar(altas_bajas, "altas_bajas.csv")

# Distribución de la respuesta en desarrollo, en escala original y logarítmica.
cuantiles <- c(0, 0.01, 0.25, 0.5, 0.75, 0.99, 1)
resumen_respuesta <- data.frame(
  escala = c("EUI (kBtu/pie²)", "log(EUI)"),
  rbind(quantile(dev$eui, cuantiles), quantile(log(dev$eui), cuantiles)),
  media = c(mean(dev$eui), mean(log(dev$eui))),
  check.names = FALSE
)
guardar(resumen_respuesta, "resumen_respuesta.csv")

# Consumos más altos que quedan en desarrollo (examen de consumo extremo).
extremos <- dev |>
  arrange(desc(eui)) |>
  select(osebuildingid, datayear, buildingtype, uso_prev, eui, eui_a2) |>
  head(10)
guardar(extremos, "extremos_desarrollo.csv")

# -----------------------------------------------------------------------------
# 7. Ventanas temporales que crecen. Para validar el año corte + 2 se entrena
#    solo con objetivos hasta el corte: la regla a - 2 vale también para las
#    etiquetas. Todo lo que se aprende (aquí, las medianas) se calcula dentro.
# -----------------------------------------------------------------------------
cortes <- c(2017, 2018, 2019)  # validan 2019, 2020 y 2021

# Referencia: EUI de a - 2; sin ella, mediana de la EUI por buildingtype
# calculada en el entrenamiento (y la mediana global si el tipo no aparece).
predecir_referencia <- function(entren, nuevos) {
  med_tipo <- entren |>
    group_by(buildingtype) |>
    summarise(med_tipo = median(eui), .groups = "drop")
  nuevos |>
    left_join(med_tipo, by = "buildingtype") |>
    mutate(pred = coalesce(eui_a2, med_tipo, median(entren$eui))) |>
    pull(pred)
}

pred_dev <- bind_rows(lapply(cortes, function(corte) {
  entren <- filter(dev, datayear <= corte)
  valid <- filter(dev, datayear == corte + 2)
  valid |>
    transmute(modelo = "referencia", ventana = corte + 2, osebuildingid, datayear,
              buildingtype, historia, y = eui,
              pred = predecir_referencia(entren, valid))
}))
guardar(pred_dev, "predicciones_desarrollo.csv")

# -----------------------------------------------------------------------------
# 8. Métricas: MAE y RMSE por ventana y reunidos, en kBtu/pie²; al reunir,
#    cada edificio-año pesa lo mismo (no se promedian los MAE de las ventanas).
# -----------------------------------------------------------------------------
resumir <- function(p) {
  summarise(p, n = n(), MAE = mean(abs(y - pred)), RMSE = sqrt(mean((y - pred)^2)),
            .groups = "drop")
}
metricas <- bind_rows(
  pred_dev |> group_by(modelo, ventana = as.character(ventana)) |> resumir(),
  pred_dev |> group_by(modelo) |> resumir() |> mutate(ventana = "reunidas")
)
guardar(metricas, "metricas_desarrollo.csv")

por_historia <- pred_dev |> group_by(modelo, historia) |> resumir()
guardar(por_historia, "metricas_por_historia.csv")
