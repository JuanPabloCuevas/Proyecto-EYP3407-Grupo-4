dicc <- read.csv("datos/diccionario.csv")
datos <- read.csv("datos/datos.csv", na.strings = c("", "NA"), stringsAsFactors = FALSE)

columnas <- c(
  "osebuildingid", "datayear", "siteeui_kbtu_sf",
  "largestpropertyusetype", "epapropertytype", "buildingtype",
  "secondlargestpropertyusetype", "thirdlargestpropertyusetype",
  "largestpropertyusetypegfa", "secondlargestpropertyuse", "thirdlargestpropertyusetypegfa",
  "propertygfatotal", "propertygfabuildings", "propertygfaparking",
  "yearbuilt", "numberoffloors", "numberofbuildings",
  "neighborhood", "zipcode"
)
base <- datos[, columnas]


# ================================================================
# 1. TRATAMIENTO INICIAL DE LOS DATOS 
# ================================================================

# ===== 1.1 Estructura: tipo de cada variable y primeros valores =====

str(base)

#Corregimos los tipos de variables

base$osebuildingid <- as.character(base$osebuildingid)
categoricas <- c("largestpropertyusetype", "epapropertytype", "buildingtype",
                 "secondlargestpropertyusetype", "thirdlargestpropertyusetype",
                 "neighborhood", "zipcode")
base[categoricas] <- lapply(base[categoricas], factor)

str(base)

#Edificios por año
table(base$datayear)

# Edificios distintos en toda la base (2015-2024)
length(unique(base$osebuildingid))


# ===== 1.3 Rangos y posibles valores de cada variable =====
sort(sapply(base, function(x) length(unique(na.omit(x)))))

numericas <- names(base)[sapply(base, is.numeric)]
round(t(sapply(base[, numericas], quantile,
               probs = c(0, 0.01, 0.5, 0.99, 1), na.rm = TRUE)), 1)

#Variable respuesta 
round(quantile(datos$siteeui_kbtu_sf, probs = c(0, 0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99, 1),
               na.rm = TRUE), 1)
round(mean(datos$siteeui_kbtu_sf, na.rm = TRUE), 1)

# Su media y mediana difieren mucho, esto por que puede tomar valores muy grandes, por esta razon usaremos la mediana para las comparaciones, debido a su mayor robustes 

# ===== 1.4 Datos faltantes ========
faltantes <- data.frame(
  n_faltantes   = colSums(is.na(base)),
  pct_faltantes = round(100 * colMeans(is.na(base)), 1)
)
faltantes[order(-faltantes$pct_faltantes), ]

# 1.4.1 Tratamientos para datos faltantes (predictores) ==========

# Crear factor para segundo y tercer uso 
for (v in c("secondlargestpropertyusetype", "thirdlargestpropertyusetype")) {
  x <- as.character(base[[v]])
  x[is.na(x)] <- "Ninguno"
  base[[v]] <- factor(x)
}

# Superficie del uso: NA -> 0
for (v in c("secondlargestpropertyuse", "thirdlargestpropertyusetypegfa")) {
  base[[v]][is.na(base[[v]])] <- 0
}

# ===== 1.4.2 Datos faltantes de la respuesta y relación con el consumo, por año =====
base$tiene_y <- !is.na(base$siteeui_kbtu_sf)

# 1. Filas con EUI (solo hasta 2021): ¿estaban sobre la mediana de su uso ese año?
con_y <- base[base$tiene_y & !is.na(base$largestpropertyusetype) & base$datayear <= 2021, ]
con_y$med_tipo <- ave(con_y$siteeui_kbtu_sf, con_y$datayear,
                      as.character(con_y$largestpropertyusetype), FUN = median)
con_y$sobre <- con_y$siteeui_kbtu_sf > con_y$med_tipo

# 2. Para cada fila sin EUI: año más cercano en que el mismo edificio sí reportó (hasta 2021)
sin_y <- base[!base$tiene_y, ]
sin_y$sobre <- sapply(seq_len(nrow(sin_y)), function(i) {
  h <- con_y[con_y$osebuildingid == sin_y$osebuildingid[i], ]
  if (nrow(h) == 0) return(NA)                    
  antes <- h[h$datayear < sin_y$datayear[i], ]
  if (nrow(antes) > 0) antes$sobre[which.max(antes$datayear)] else h$sobre[which.min(h$datayear)]
})

# 3. Tabla por año
anios <- factor(sin_y$datayear, levels = 2015:2024)
tabla <- data.frame(
  registros   = as.vector(table(base$datayear)),
  sin_eui     = as.vector(tapply(!base$tiene_y, base$datayear, sum)),
  comparados  = as.vector(tapply(!is.na(sin_y$sobre), anios, sum)),
  pct_sobre   = as.vector(round(100 * tapply(sin_y$sobre, anios, mean, na.rm = TRUE))),
  row.names   = 2015:2024
)
tabla$pct_sin_eui <- round(100 * tabla$sin_eui / tabla$registros, 1)
tabla[, c("registros", "sin_eui", "pct_sin_eui", "comparados", "pct_sobre")]

# Totales y referencia
sum(!is.na(sin_y$sobre)); round(100 * mean(sin_y$sobre, na.rm = TRUE))   
round(100 * mean(con_y$sobre))                                           

#Con esto podemos concluir que no hay patrones sitematcios en los edificios con datos faltantes en el año 2021, por lo que no se esperaria un sesgo al quitarlos

# Tratamiento a los datos faltantes en respuesta ya se hizo, la variable tiene_y es un marcador


# ===== 1.5 Valores sospechosos =====
sum(base$siteeui_kbtu_sf > 1000, na.rm = TRUE)    # EUI extremas
base[which(base$siteeui_kbtu_sf > 1000),
     c("osebuildingid", "datayear", "largestpropertyusetype", "siteeui_kbtu_sf")]
sum(base$propertygfaparking < 0, na.rm = TRUE)     # estacionamiento negativo
sum(base$numberoffloors == 0, na.rm = TRUE)        # 0 pisos
sum(base$numberofbuildings == 0, na.rm = TRUE)     # 0 edificios
sum(base$yearbuilt == 1900, na.rm = TRUE)          
sum(base$yearbuilt > base$datayear, na.rm = TRUE)  # construido después del registro
sum(duplicated(base[, c("osebuildingid", "datayear")]))

# ---- Tratamiento ----
# Regla: EUI > 1000 y más de 10 veces la mediana de su uso principal (mediana de desarrollo, <= 2021)
dev     <- base[base$datayear <= 2021 & !is.na(base$siteeui_kbtu_sf), ]
med_dev <- tapply(dev$siteeui_kbtu_sf, as.character(dev$largestpropertyusetype), median)
razon   <- base$siteeui_kbtu_sf / med_dev[as.character(base$largestpropertyusetype)]

error_eui <- !is.na(razon) & base$siteeui_kbtu_sf > 1000 & razon > 10
sum(error_eui)                                                    
base[error_eui, c("osebuildingid", "datayear", "largestpropertyusetype", "siteeui_kbtu_sf")]
base$siteeui_kbtu_sf[error_eui] <- NA                             # se tratan como faltantes

# ---- Valores imposibles en predictores ----
base$propertygfaparking[base$propertygfaparking < 0] <- 0

# ---- Respuesta: marcar (después de corregir errores) ----
base$tiene_y <- !is.na(base$siteeui_kbtu_sf)


# ================================================================
# 2. CONSTRUCCIÓN DE LA BASE ANALÍTICA
# ================================================================

predictores <- c(
  "largestpropertyusetype", "epapropertytype", "buildingtype",
  "secondlargestpropertyusetype", "thirdlargestpropertyusetype",
  "largestpropertyusetypegfa", "secondlargestpropertyuse", "thirdlargestpropertyusetypegfa",
  "propertygfatotal", "propertygfabuildings", "propertygfaparking",
  "yearbuilt", "numberoffloors", "numberofbuildings",
  "neighborhood", "zipcode"
)

# ---- 2.1 Historia: lo observado en a-2, asignado al año objetivo a ----
hist <- base[, c("osebuildingid", "datayear", "siteeui_kbtu_sf", predictores)]
names(hist)[names(hist) == "siteeui_kbtu_sf"] <- "eui_lag2"
hist$datayear <- hist$datayear + 2
hist$en_a2 <- TRUE

# ---- 2.2 Respuestas del año a ----
resp <- base[, c("osebuildingid", "datayear", "siteeui_kbtu_sf", "tiene_y")]

# ---- 2.3 Unir respuesta (a) con historia (a-2) ----
modelo <- merge(resp, hist, by = c("osebuildingid", "datayear"), all.x = TRUE)
modelo$en_a2[is.na(modelo$en_a2)] <- FALSE
modelo <- modelo[modelo$datayear >= 2017, ]          # años objetivo 2017-2024

# ---- 2.4 Filtros de la muestra y tabla de construcción ----
periodo <- function(a) factor(ifelse(a <= 2021, "Desarrollo",
                                     ifelse(a == 2022, "2022 (solo historia)", "Prueba")),
                              levels = c("Desarrollo", "2022 (solo historia)", "Prueba"))

paso1 <- modelo                                           # años objetivo 2017-2024
paso2 <- paso1[paso1$tiene_y, ]                           # con respuesta válida
paso3 <- paso2[paso2$en_a2, ]                             # con registro del edificio en a-2
paso4 <- paso3[!is.na(paso3$largestpropertyusetype), ]    # con uso principal en a-2

construccion <- rbind(
  "1. Registros con año objetivo 2017-2024" = table(periodo(paso1$datayear)),
  "2. Con respuesta válida"                 = table(periodo(paso2$datayear)),
  "3. Con registro del edificio en a-2"     = table(periodo(paso3$datayear)),
  "4. Con uso principal en a-2"             = table(periodo(paso4$datayear))
)
construccion

# ---- 2.5 Variables finales ----
analitica <- paso4
analitica$tiene_hist <- !is.na(analitica$eui_lag2)                      
analitica$antiguedad <- pmax(analitica$datayear - analitica$yearbuilt, 0) 
analitica$periodo    <- periodo(analitica$datayear)

categoricas <- c("largestpropertyusetype", "epapropertytype", "buildingtype",
                 "secondlargestpropertyusetype", "thirdlargestpropertyusetype",
                 "neighborhood", "zipcode")
analitica[categoricas] <- lapply(analitica[categoricas], factor)

# ---- 2.6 Verificaciones ----
dim(analitica)
sum(is.na(analitica$siteeui_kbtu_sf))       
tapply(analitica$tiene_hist, analitica$datayear, function(x) round(100 * mean(x), 1))

pasos <- list(paso1, paso2, paso3, paso4)
edificios <- t(sapply(pasos, function(p)
  tapply(p$osebuildingid, periodo(p$datayear), function(x) length(unique(x)))))
rownames(edificios) <- rownames(construccion)
edificios

# ---- 2.7 Distribución de la muestra ----

y_dev <- analitica$siteeui_kbtu_sf[analitica$periodo == "Desarrollo"]
summary(y_dev)

par(mfrow = c(1, 2))
p99 <- quantile(y_dev, 0.99)
hist(y_dev[y_dev <= p99], breaks = 60,
     main = "EUI, años de desarrollo", xlab = "EUI (kBtu/pie²)", ylab = "Frecuencia")
hist(log(y_dev), breaks = 60,
     main = "log(EUI), años de desarrollo", xlab = "log(kBtu/pie²)", ylab = "Frecuencia")
par(mfrow = c(1, 1)) 

round(quantile(y_dev, probs = c(0, 0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99, 1)), 1)
round(mean(y_dev), 1)

#Cobertura geografica
sort(table(analitica$neighborhood[analitica$periodo == "Desarrollo"]), decreasing = TRUE)   # cobertura geográfica


# ================================================================
# 3. PARTICIONES TEMPORALES
#    Validación cruzada temporal con ventanas de origen creciente.
#    Para evaluar el año a se entrena solo con respuestas hasta a-2.
# ================================================================

ventanas <- list(
  v2019 = list(entrena = 2017,      evalua = 2019),
  v2020 = list(entrena = 2017:2018, evalua = 2020),
  v2021 = list(entrena = 2017:2019, evalua = 2021)
)

# Partición final: se entrena con 2017-2021 y se evalúa UNA sola vez en 2023-2024
final <- list(entrena = 2017:2021, evalua = c(2023, 2024))

# ---- 3.2 Función para separar entrenamiento y evaluación ----
separar <- function(v) {
  list(
    entrena = analitica[analitica$datayear %in% v$entrena, ],
    evalua  = analitica[analitica$datayear %in% v$evalua, ]
  )
}

# ---- 3.3 Verificaciones ----
resumen_particiones <- do.call(rbind, lapply(c(ventanas, list(final = final)), function(v) {
  p <- separar(v)
  data.frame(
    entrena_anios   = paste(range(v$entrena), collapse = "-"),
    evalua_anios    = paste(v$evalua, collapse = ", "),
    filas_entrena   = nrow(p$entrena),
    filas_evalua    = nrow(p$evalua),
    brecha_ok       = max(v$entrena) <= min(v$evalua) - 2   # se respeta a-2
  )
}))
resumen_particiones


