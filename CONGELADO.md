# Decisiones congeladas antes de evaluar en prueba

Fecha: 2026-11-08, 21:30 UTC. Hasta este momento no se ha calculado ninguna métrica ni resumen con las respuestas de 2023 y 2024. Lo único que se revisó de esas filas fueron sus predictores: faltantes, categorías nuevas y la historia disponible.

## Población y respuesta

- Una fila es un edificio–año objetivo. La respuesta es `siteeui_kbtu_sf`, en kBtu/pie².
- Desarrollo: objetivos 2017–2021. Quedan 16 650 filas de 3607 edificios con respuesta y sin errores de registro.
- Prueba: objetivos 2023 y 2024. 2022 solo sirve como historia para predecir 2024.
- Se excluyen las filas sin respuesta; no se imputan.
- Regla de errores de registro, fijada en la sección 1: un registro es error si su EUI supera 10 veces la mediana de las EUI anteriores del mismo edificio y además supera 1000 kBtu/pie². Ese registro no se usa ni como objetivo ni como historia. Se aplica igual en prueba.

## Información admisible

- Para predecir el año a solo se usan registros de años ≤ a − 2. La misma regla vale para las etiquetas de entrenamiento.
- Los atributos copiados a todos los años se usan bajo el supuesto declarado de características estables.

## Variables

- Historia: log de la última EUI válida hasta a − 2, si no hay historia, si la historia es antigua, log de la EUI de a − 3 y si falta.
- Uso, según el último registro ≤ a − 2: uso principal, fracción del uso principal y número de usos, con indicadora de faltante.
- Edificio: log de la superficie, fracción de estacionamiento, antigüedad, log de pisos, log de número de edificios, tipo y barrio.

## Modelos y búsqueda (sección 2)

- Lasso: 20 valores de λ entre 0,6019 y 0,0006019.
- GAM: 3 fórmulas, con la suavidad elegida por REML.
- Bosque aleatorio: 12 configuraciones (mtry ∈ {3, 5, 8, 12}, nodo ∈ {5, 20, 50}), con 300 árboles.
- Todos se ajustan sobre log(EUI) y se retransforman con exp(), así que predicen la mediana condicional.

## Métrica y regla de selección

- Métrica principal: MAE reunido de las ventanas, en kBtu/pie². RMSE como métrica complementaria.
- Regla: el menor MAE reunido, dentro de cada familia y entre familias.
- Procedimiento elegido: **lasso con λ = 0,005332** (posición 14 de la grilla).
- En prueba también se informan el GAM G1 y el bosque (mtry 5, nodo 5), pero no se usan para elegir nada.

## Ajuste final y comparación

- El ajuste final usa los objetivos 2017–2021. Todo el preprocesamiento se aprende de ese entrenamiento.
- Referencia principal, según la ficha del caso: la EUI de a − 2. Si no existe, la mediana por tipo del entrenamiento.
- Referencia alternativa, fijada ahora, antes de mirar las respuestas de prueba: la última EUI válida hasta a − 2 y, si no hay ninguna, la mediana por tipo. Se informa como comparación y no participa en la selección.
  - Motivo: en prueba, 631 de 7001 filas tienen historia anterior pero no EUI en a − 2; en desarrollo eran 75 de 10 035.
  - La diferencia viene de que en 2021 faltan 419 valores de EUI y en 2022, 345.

## Incertidumbre

- Se calcula la diferencia de MAE entre el procedimiento elegido y la referencia.
- Se remuestrean edificios con reposición, con 2000 réplicas y semilla 3407. Las predicciones quedan fijas.
- Se informa el intervalo de percentiles 95 %, reunido y por año. El intervalo es condicional a los ajustes: no incluye la incertidumbre de selección ni la de otros años.

## Código congelado (md5)

```
8468a048d0cf65e0e88cb871487cfb36  analisis.R
6e8193aabf4154a340142792fae5682a  R/01_base.R
aaccacd9d2e2debde8550cf9277c2cb0  R/02_modelos.R
213393a1e49cedaffcbe57c337210f27  R/03_prueba.R
```

## Cambios posteriores a la evaluación en prueba

2026-11-08, 21:55 UTC. `R/01_base.R`, `R/02_modelos.R` y `R/03_prueba.R` siguen con los mismos md5 que aparecen arriba. Solo cambió `analisis.R`, por dos motivos:

1. Se agregó la sección 4 (`R/04_diagnostico.R`), que describe la prueba ya evaluada y calcula las sensibilidades en desarrollo.
2. Se fijó un orden alfabético independiente del idioma del equipo (`LC_COLLATE = C`) y se activó UTF-8 para que las figuras muestren tildes. El orden de las categorías define la categoría base del lasso, así que sin este ajuste un equipo configurado en otro idioma podría obtener un lasso distinto.

Con esos cambios, todas las tablas y predicciones de las secciones 1 a 3 salen idénticas byte a byte. Solo cambian `sessionInfo.txt`, que registra el idioma de la sesión, y los segundos de `tiempos_busqueda.csv`.

```
bf18543c1184bb067c3af5fa2843655b  analisis.R
835c2df2c7765197add86d0c82031666  R/04_diagnostico.R
```

## Cambios posteriores para el informe

2026-11-08, 23:30 UTC. `R/01_base.R`, `R/02_modelos.R` y `R/03_prueba.R` siguen con los md5 de la primera sección. Ningún cambio toca la población, las variables, los ajustes, la selección ni las predicciones:

1. `R/04_diagnostico.R`: solo cambió la parte de figuras. Se dibujan al tamaño en que se imprimen (300 dpi), con títulos y leyendas más breves, coma decimal en los ejes y los símbolos ≥ y –. Sus nombres siguen la numeración del informe: `fig1_error_y_cambio_por_anio.png` pasó a ser `fig3_error_y_cambio_por_anio.png`, y `fig2_observado_vs_predicho_prueba.png`, `fig4_observado_vs_predicho_prueba.png`.
2. `R/05_informe.R`, nuevo: dibuja la construcción de la muestra (figura 1) y el diseño temporal (figura 2), escribe `auditoria_columnas.csv` y `tiempo_ejecucion.csv` y genera el informe. No ajusta modelos.
3. `informe.Rmd`, nuevo: fuente del informe. Lee todas sus cifras de `resultados/` y no se genera si alguna afirmación del texto deja de cumplirse.
4. `analisis.R`: registra la hora de inicio, comprueba al comienzo los paquetes y pandoc (antes de fijar la semilla y sin cargar los paquetes del análisis) y ejecuta `R/05_informe.R` al final.
5. `verificacion/fuga.R`, nuevo: prueba de fuga que `analisis.R` no ejecuta. Su resultado queda en `verificacion/resultado_fuga.txt`.

En una copia limpia, con `datos/` recién descomprimido del .zip, los 63 archivos de tablas y predicciones que comparte con la corrida anterior salieron idénticos byte a byte. Solo cambiaron `sessionInfo.txt`, por los paquetes cargados, y los segundos de `tiempos_busqueda.csv`. Los archivos nuevos son `auditoria_columnas.csv`, `tiempo_ejecucion.csv` y las cuatro figuras.

```
f5fe034e67780bac52e772781002b137  analisis.R
0c177a50952438e9a22987316d2c8357  R/04_diagnostico.R
f46865167d3c6d388dd58363b49c3594  R/05_informe.R
d2a9e8fd706587fe966b197895c5ac98  informe.Rmd
f72878c46660fa15bdcdd02120549d78  verificacion/fuga.R
```

## Revisión del informe contra el enunciado

2026-11-09, 02:55 UTC. `R/01_base.R`, `R/02_modelos.R` y `R/03_prueba.R` siguen con los md5 de la primera sección. Ningún cambio toca la población, las variables, los ajustes, la selección ni las predicciones:

1. `R/04_diagnostico.R`: agrega el error en prueba por uso principal (`diag_prueba_uso.csv`), que pide la ficha. Conservan su nombre los usos con al menos 300 filas en el entrenamiento final, una regla que no mira la prueba. La Figura 4 pasa a 4,0 × 3,6 pulgadas.
2. `R/05_informe.R`: agrega la cobertura geográfica, los identificadores y las superficies (`auditoria_complementaria.csv`), la relación de cada unión, sus filas y edificios antes y después y las filas que comparten un registro (`uniones.csv`) y las categorías que el preprocesamiento agrupa en el entrenamiento final (`categorias_entrenamiento_final.csv`); solo describen los datos. Fija el mismo idioma que `analisis.R`, porque al correrlo solo el informe no se generaba en una sesión sin UTF-8, y su aviso distingue la falta de LaTeX de otros errores.
3. `analisis.R`: imprime el error por uso.
4. `informe.Rmd`: revisión contra el enunciado. Agrega interpretación y tipo a la tabla de variables; las condiciones de uso de los datos (dominio público según los metadatos del conjunto); las uniones, la cobertura geográfica, los identificadores, las superficies y las categorías poco frecuentes; el error por uso (Anexo A.8) y cómo cambia la conclusión en S1 y S2. Además calcula cifras que estaban escritas a mano: las de la leyenda de la Figura 1, las configuraciones de las tablas 3 y 4 y la configuración que elegía la regla de un error estándar.

En una copia limpia, con `datos/` recién descomprimido del .zip, 68 de los 71 archivos de `resultados/` de la corrida anterior salieron idénticos byte a byte, entre ellos todas las tablas y predicciones. Solo cambiaron la Figura 4, por su nuevo tamaño, y los segundos de `tiempos_busqueda.csv` y `tiempo_ejecucion.csv`.

```
7a0754fd14d3964ea3999b6bfd3e95c9  analisis.R
880e5b363bced3d5986a3911a25871b8  R/04_diagnostico.R
6fa91880b8c07923969a15c8d9b2aa98  R/05_informe.R
5f46cf86a76fee8e8ad65a95f43cef94  informe.Rmd
```

## Nombres de los integrantes

Después de la revisión solo se agregó a la cabecera de `analisis.R` una línea de comentario con los nombres de los integrantes. Por eso su md5 ya no es el de arriba, pero el código que se ejecuta es idéntico: quitando esa línea y la línea `#` que la precede, el archivo vuelve a tener el md5 7a0754fd14d3964ea3999b6bfd3e95c9.

## Versiones de paquetes en el informe

2026-11-09, 13:15 UTC. En otro computador (Windows), `utils::packageDescription()` devolvió NA para un paquete y el informe se detenía en la sección de reproducibilidad. `informe.Rmd` ahora toma la versión del paquete cargado (`getNamespaceVersion()`) y, si no, la instalada. Solo cambia cómo se escribe esa línea del informe; el análisis, las tablas y las predicciones no cambian.

## Redacción del informe, Figura 2 y descripción de la respuesta

2026-11-09, 20:00 UTC. `R/01_base.R`, `R/02_modelos.R`, `R/03_prueba.R` y `R/04_diagnostico.R` no cambian. Ningún cambio toca la población, las variables, los ajustes, la selección ni las predicciones:

1. `R/05_informe.R`: la Figura 2 se redibuja como una grilla de ajustes por año del reporte, con la misma información. Se agrega la sección 1d, que describe la respuesta en 2015–2022 sin los errores de registro: fracción de la variación entre edificios, persistencia respecto de $a-2$, cambio según el nivel y asimetría (`descriptiva_varianza.csv`, `descriptiva_persistencia.csv`, `descriptiva_cambio_nivel.csv` y `descriptiva_escala.csv`). Solo describe los datos y no lee la prueba.
2. `informe.Rmd` y `plantilla/`: el informe usa la plantilla de informes UC (portada, encabezado y estilos), adaptada para generarse desde R Markdown con pdflatex. Redacción revisada y más breve (el cuerpo pasa de algo más de 12 a 11 páginas), descripción de la respuesta en la sección 2.2 y en el Anexo A.3, referencias a las clases del curso y seis comprobaciones nuevas para las afirmaciones agregadas.

En una corrida completa, los archivos de tablas y predicciones de la versión anterior salieron idénticos byte a byte.

```
6715ad0d776e85f049f5ae0c03a23d2e  R/05_informe.R
527ce493046cfb619104d8da1fcfe0b6  informe.Rmd
a9851e0cfeb436af13911f5ec709c350  plantilla/style.cls
feee272f96d8647f15ad937228a01c13  plantilla/informe-uc.tex
```

## Revisión de la redacción por el equipo

2026-11-10, 18:00 UTC. Solo cambia `informe.Rmd`; el código del análisis, las tablas de `resultados/` y las predicciones no cambian:

1. Redacción revisada por el equipo en todas las secciones y referencias en una página aparte; la descripción de la respuesta pasa a su propia sección (2.6) y las variables, a la 2.7. Se agregan contribuciones, declaración de IA, enlace del repositorio y citas a las sesiones S12, S14, S16 y S17.
2. La Tabla 2 se agrupa por decisión (usadas y excluidas, separadas por una línea) y la Tabla 6 se reduce a la referencia alternativa y el lasso, en bloques por tipo y por quintil de superficie. Las cifras son las mismas.
3. Dos comprobaciones nuevas: 35 configuraciones con a lo más 20 por familia, y mediana de predicción menos observación negativa en los consumos extremos.

```
fd2e29fe72a05ca2bf8ecdb51adc989c  informe.Rmd
```
