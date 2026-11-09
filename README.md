# Intensidad energética anual de edificios de Seattle

EYP3407 Tópicos Aplicados en Estadística · Segundo semestre 2026 · Proyecto aplicado, caso 04.

**Integrantes:** Juan Pablo Cuevas, Cristóbal Honorato, Michelle Houngbo, Maximiliano León.

¿Qué tan bien se anticipa la intensidad energética anual (EUI, kBtu/pie²) de un edificio conocido con la información disponible hasta dos años antes? Comparamos un lasso, un GAM y un bosque aleatorio con la persistencia de la EUI de a − 2, en ventanas temporales que validan 2019, 2020 y 2021, y en una prueba única en 2023 y 2024. El informe está en `informe.pdf`, y su fuente ejecutable, en `informe.Rmd`.

## Ejecución

Desde la raíz del repositorio, con los datos en `datos/`:

```
Rscript --vanilla analisis.R
```

Ese único comando lee los datos, construye la base analítica y las particiones, ajusta y evalúa los modelos, escribe tablas, predicciones y figuras en `resultados/` y genera `informe.pdf` desde `informe.Rmd`. No hay pasos manuales. En la prueba registrada abajo tardó 4,2 minutos.

Para regenerar solo el informe después de una corrida completa, sin reajustar modelos:

```
Rscript --vanilla R/05_informe.R
```

## Entorno

Versión probada:

- R 4.3.3 en Ubuntu 24.04.5 LTS, con 4 núcleos; los modelos usan un núcleo.
- Paquetes de R: dplyr 1.1.4, glmnet 4.1-8, mgcv 1.9-1, ranger 0.16.0, rmarkdown 2.25 y knitr 1.45. La lista completa queda en `resultados/sessionInfo.txt`.
- pandoc 3.1.3 y TeX Live 2023 (pdflatex).

Requisitos mínimos: R 4.1 o posterior (el código usa el operador `|>`; en Windows conviene R 4.2 o posterior, que trabaja en UTF-8) y dplyr 1.1.0 o posterior. `analisis.R` comprueba al inicio que estén los paquetes y pandoc, y se detiene con un mensaje si falta algo.

Instalación de los paquetes de R:

```r
install.packages(c("dplyr", "glmnet", "mgcv", "ranger", "rmarkdown", "knitr"))
```

- **pandoc 2.0 o posterior:** viene con RStudio y con Quarto. Si se ejecuta desde una terminal sin ellos, instálelo desde <https://pandoc.org/installing.html> o indique su carpeta en la variable de entorno `RSTUDIO_PANDOC`.
- **LaTeX, para el PDF:** lo más simple es TinyTeX, con `install.packages("tinytex")` y luego `tinytex::install_tinytex()`; con TinyTeX, los paquetes de LaTeX que falten se instalan solos al compilar. En Ubuntu o Debian también sirve `sudo apt install texlive-latex-recommended texlive-latex-extra texlive-fonts-recommended texlive-lang-spanish lmodern`. Sin LaTeX, el informe se genera en HTML y la ejecución lo avisa.

## Datos

- **Archivo:** `caso04_seattle_edificios.zip`, copia preparada para el curso el 12 de octubre de 2026. Contiene `datos.csv` (34 699 registros edificio–año de 2015 a 2024, 46 columnas), `diccionario.csv` y `LEEME.txt`.
- **Fuente:** City of Seattle, Office of Sustainability and Environment, *Building Energy Benchmarking Data, 2015-Present* (programa *Seattle Building Energy Benchmarking*), portal de datos abiertos de Seattle (data.seattle.gov), conjunto `teqw-tu6e`. `datos/LEEME.txt` registra la consulta a la API del portal con que se preparó la copia.
- **Cómo obtenerlo:** [completar: enlace de descarga del .zip, por ejemplo el de Canvas del curso o el del propio repositorio]. Luego se descomprime en `datos/`, donde quedan los tres archivos sin subcarpetas:

  ```
  unzip caso04_seattle_edificios.zip -d datos/
  ```

- **Copia conservada:** `datos/` contiene la copia usada durante el desarrollo, sin editar (12 MB). Huellas md5 para comprobarla:

  | Archivo | md5 |
  |---|---|
  | `caso04_seattle_edificios.zip` | `2e3b55048c45e614c42b93ba0371ee05` |
  | `datos/datos.csv` | `bc623281c6ad5a50017d5f0d8e2a3b1a` |
  | `datos/diccionario.csv` | `85278960e492d18f1f80214d6bdbf8ab` |
  | `datos/LEEME.txt` | `9f3665ec76174e8e955d1cc177d659bd` |

- **Condiciones de reutilización:** dominio público. Los metadatos del conjunto en el portal (<https://data.seattle.gov/api/views/teqw-tu6e.json>, la misma consulta que registra `LEEME.txt`) indican `"licenseId" : "PUBLIC_DOMAIN"` y atribuyen los datos a la Office of Sustainability and Environment; se consultaron el 9 de noviembre de 2026. Por eso `datos/` puede publicarse en el repositorio, citando a esa oficina.

## Estructura

```
README.md              este archivo
analisis.R             punto de entrada
R/01_base.R            base analítica, regla de errores de registro, ventanas y referencia
R/02_modelos.R         lasso, GAM y bosque en las ventanas de desarrollo; búsqueda y selección
R/03_prueba.R          ajuste final y evaluación única en 2023-2024, con remuestreo de edificios
R/04_diagnostico.R     análisis de errores (tipo, uso, tamaño, historia, extremos), sensibilidades S1 y S2,
                       control de la regla, figuras 3 y 4
R/05_informe.R         figuras 1 y 2; auditorías de columnas, superficies, identificadores, uniones y
                       categorías; tiempo de ejecución e informe
informe.Rmd            fuente ejecutable del informe
informe.pdf            informe generado
CONGELADO.md           decisiones congeladas antes de abrir la prueba y registro de cambios
verificacion/fuga.R    prueba de fuga de información (opcional; analisis.R no la ejecuta)
datos/                 archivos del paquete del caso
resultados/            tablas, predicciones y figuras (se regeneran)
presentacion.pdf       [pendiente]
```

## Control de ejecución

- **Semillas:** 3407 en `analisis.R`, en cada bosque (`seed = 3407`), en el remuestreo de edificios (2000 réplicas) y en la muestra de la sensibilidad S2. La prueba de fuga usa 99 para alterar los datos.
- **Particiones:** las reglas están en `R/01_base.R` y `R/02_modelos.R`. Las ventanas de desarrollo entrenan con objetivos hasta a − 2 y validan 2019, 2020 y 2021; el ajuste final usa los objetivos 2017-2021 y se evalúa una sola vez en 2023 y 2024.
- **Predicciones:** `resultados/predicciones_desarrollo.csv` (referencia), `resultados/predicciones_elegidas.csv` (configuración elegida de cada familia en desarrollo) y `resultados/predicciones_prueba.csv`. Con ellas se recalculan todas las métricas.
- **Idioma del equipo:** `analisis.R` fija `LC_COLLATE = C`, porque el orden alfabético de las categorías define la categoría base del lasso.
- **Congelamiento:** `CONGELADO.md` registra, con fecha y huellas md5 del código, las decisiones tomadas antes de abrir la prueba y cada cambio posterior.

## Prueba desde una copia limpia

- **Fecha:** 9 de noviembre de 2026, 02:38 UTC.
- **Copia:** una carpeta nueva con `analisis.R`, `R/`, `informe.Rmd`, `CONGELADO.md`, `README.md`, `.gitignore` y `verificacion/fuga.R`, más `datos/` recién descomprimido de `caso04_seattle_edificios.zip` (las huellas md5 coinciden con la tabla de arriba). No contenía `resultados/` ni `informe.pdf`.
- **Entorno:** R 4.3.3 en Ubuntu 24.04.5 LTS, 4 núcleos, con los paquetes ya instalados. Es el mismo equipo en que se desarrolló el análisis, no un computador distinto.
- **Comando:** `Rscript --vanilla analisis.R`
- **Resultado:** terminó sin errores ni advertencias en 4,2 minutos y generó `informe.pdf` (19 páginas) y 75 archivos en `resultados/`. Frente a la corrida anterior, del 8 de noviembre, 68 de sus 71 archivos quedaron idénticos byte a byte, entre ellos todas las tablas y predicciones; cambiaron la Figura 4, que se achicó, y los segundos de `tiempos_busqueda.csv` y `tiempo_ejecucion.csv`. Los cuatro archivos nuevos son `diag_prueba_uso.csv`, `auditoria_complementaria.csv`, `uniones.csv` y `categorias_entrenamiento_final.csv`.
- **Prueba de fuga:** `Rscript --vanilla verificacion/fuga.R` en la misma copia, el 9 de noviembre de 2026 a las 02:44 UTC; tardó 10,9 minutos. Al alterar la EUI y los usos de los años posteriores a cada corte, las predicciones de las 35 configuraciones y de la referencia en 2019–2021, y las de los cinco procedimientos en 2023–2024, quedaron idénticas; las que sí usaban años alterados cambiaron. El detalle queda en `verificacion/resultado_fuga.txt`.
- **Prueba del equipo en otro computador (enunciado 6.3):** 9 de noviembre de 2026, 16:15–16:25 (hora de Chile), por Juan Pablo Cuevas.
  - *Entorno:* Windows 11 x64 (build 26200), 12 núcleos; R 4.5.3 con dplyr 1.2.1, glmnet 5.2, mgcv 1.9-5, ranger 0.18.0, rmarkdown 2.32 y knitr 1.52; pandoc 3.13 y TinyTeX (TeX Live 2025). Los paquetes se instalaron con `install.packages()` y pandoc con `winget`.
  - *Copia:* carpeta nueva fuera del repositorio con `analisis.R`, `R/`, `informe.Rmd`, `CONGELADO.md`, `README.md`, `.gitignore`, `verificacion/` y `datos/` (md5 de `datos.csv` igual al de la tabla de arriba), sin `resultados/` ni `informe.pdf`.
  - *Comando:* `Rscript --vanilla analisis.R`
  - *Resultado:* terminó sin errores ni advertencias en 9,8 minutos y generó `informe.pdf` y `resultados/`. Frente a los resultados del repositorio, la referencia, el lasso (coeficientes, métricas y predicciones) y el bosque salieron idénticos; el GAM difiere como máximo en 2,3 × 10⁻¹⁰ kBtu/pie², atribuible a la versión de mgcv. Ninguna cifra del informe cambia.

## Contribuciones

[completar: síntesis de los aportes de cada integrante]

## Declaración de uso de IA

[pendiente]
