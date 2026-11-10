---
title: "Intensidad energética anual de edificios de Seattle: ¿cuánto se puede anticipar con información hasta dos años antes?"
subtitle: "EYP3407 Tópicos Aplicados en Estadística · Proyecto aplicado, caso 04"
author: ["Juan Pablo Cuevas", "Cristóbal Honorato", "Michelle Houngbo", "Maximiliano León"]
grupo: "Grupo 4"
date: "10 de noviembre de 2026"
lang: es
output:
  pdf_document:
    template: plantilla/informe-uc.tex
    number_sections: true
    fig_caption: true
    latex_engine: pdflatex
  html_document:
    number_sections: true
header-includes:
  - \DeclareUnicodeCharacter{2212}{\ensuremath{-}}
  - \DeclareUnicodeCharacter{2264}{\ensuremath{\leq}}
  - \DeclareUnicodeCharacter{2265}{\ensuremath{\geq}}
  - \setlength{\emergencystretch}{3em}
---





# Resumen ejecutivo

El programa de reporte energético de Seattle recibe cada año la intensidad energética (EUI, en kBtu/pie²) de más de 3000 edificios, pero en enero del año $a$ el reporte de $a-1$ todavía está incompleto. Por lo tanto, evaluamos qué tan bien se puede anticipar la EUI anual de un edificio conocido usando solo información hasta $a-2$.

Con los años de validación 2019–2021, ningún modelo superó a la referencia de la ficha, que simplemente repite la EUI de $a-2$. Entre los tres procedimientos elegimos un lasso sobre log(EUI), el de menor error. En la prueba 2023–2024, el lasso se equivocó en promedio en 9,86 kBtu/pie², 0,84 menos que la referencia (IC 95 %: [−1,40; −0,23]). Sin embargo, casi toda esa ventaja (0,69) viene de 631 casos sin dato en $a-2$: ahí la referencia usa la mediana del tipo de edificio, mientras el lasso usa el último dato del edificio. Si la referencia también usa ese último dato, la diferencia baja a −0,15 kBtu/pie² y el intervalo [−0,63; 0,38] incluye el 0, es decir, no hay una mejora clara.

Finalmente, recomendamos predecir la EUI con el último dato reportado por el propio edificio. El lasso sirve sobre todo para edificios sin historia, y no conviene usarlo en edificios de consumo muy alto (≥ 283 kBtu/pie²), porque subestima su consumo. La principal limitación es que la prueba cubre solo dos años, y choques que afectan a todos los edificios a la vez, como la pandemia, pueden cambiar los resultados de un año a otro.

# Problema y datos

## Pregunta y uso

La pregunta planteada es si se puede anticipar la intensidad energética anual de un edificio ya conocido a partir de sus características (tipo, tamaño, uso) y de lo que reportó en años anteriores (EYP3407, 2026). Un modelo que responda lo anterior sería útil para quien administra el programa de reporte, pues al comenzar el año necesita una estimación para cada edificio, por ejemplo para decidir a cuáles hacer seguimiento, sin esperar el reporte de $a-1$, que todavía está incompleto.

Para evaluar el modelo simulamos cómo se habría usado en el pasado. Para predecir, por ejemplo, la EUI de 2019, solo usamos los reportes hasta 2017. El problema es que solo tenemos la base descargada en 2026, no la que existía en enero de 2019. Por eso suponemos que los reportes hasta 2017 que vemos hoy son iguales a los que se conocían en esa fecha. Si alguno se corrigió después, el modelo usó un dato algo mejor que el disponible en su momento, y la evaluación resulta un poco optimista (sección 3.2).

## Población, unidad y respuesta

Una fila es un edificio–año objetivo, con clave `osebuildingid` y `datayear`, que el código verifica que no se repite. La respuesta es `siteeui_kbtu_sf`, la energía consumida en el sitio durante el año dividida por la superficie bruta. Se utiliza cada edificio con un reporte válido en el año objetivo, tenga o no historia y aunque deje de reportar después. Por otro lado, las filas sin respuesta se excluyen y no se imputan. Por ende, las conclusiones valen para los edificios del programa que reportan, no para los que dejaron de hacerlo.

## Procedencia

Los datos provienen del programa *Seattle Building Energy Benchmarking*, que la ciudad publica como *Building Energy Benchmarking Data, 2015-Present* (conjunto `teqw-tu6e`; City of Seattle, 2026). Según los metadatos del portal, consultados el 9 de noviembre de 2026, son de dominio público. Usamos la copia del curso, `caso04_seattle_edificios.zip`, preparada el 12 de octubre de 2026, cuyo `datos.csv` tiene 34 699 registros edificio–año de 3823 edificios y 46 columnas. Los archivos originales no se editan, cualquier filtro y transformación está en el código. Como solo tenemos la versión descargada, un valor antiguo puede incluir correcciones posteriores.

## Construcción de la muestra

\begin{table}[!htb]

\caption{\label{tab:tabla-muestra}Construcción de la muestra. Desarrollo: objetivos 2017–2021, de los que se evalúan 2019–2021 (2017 y 2018 solo entrenan). Prueba: objetivos 2023–2024.}
\centering\small
\begin{tabular}[t]{lrrrr}
\toprule
Paso & Desarrollo: filas & Desarrollo: edificios & Prueba: filas & Prueba: edificios\\
\midrule
Filas objetivo del período & 17 255 & 3632 & 7399 & 3749\\
Con respuesta (EUI del año) & 16 657 & 3607 & 7006 & 3640\\
Sin errores de registro & 16 650 & 3607 & 7001 & 3638\\
Filas evaluadas & 10 035 & 3575 & 7001 & 3638\\
\bottomrule
\end{tabular}
\end{table}

Como cada predicción usa información hasta dos años antes, los años 2015, 2016 y 2022 no se predicen, solo aportan historia. Los años objetivo de desarrollo son 2017–2021 y los de prueba, 2023–2024 (Tabla 1 y Figura 1). En ambos excluimos las filas sin EUI del año (598 en desarrollo y 393 en prueba) y las marcadas como error de registro (7 y 5; sección 2.5).

No todas las filas tienen la EUI de $a-2$, porque cada año entran edificios nuevos (entre 50 y 93) y otros no reportan algún año. Esto pesa mucho más en la prueba, pues en 2021 y 2022 faltan 419 y 345 respuestas, frente a 33–57 por año antes de 2021. Por eso, 631 filas de prueba (9,0 %) solo tienen historia anterior a $a-2$, contra 75 (0,7 %) en desarrollo. A las 24 654 filas objetivo (3813 edificios) se unen la EUI de $a-2$ y la de $a-3$ por la clave edificio–año, de uno a uno, y la última EUI válida y el uso por el registro más reciente $\leq a-2$ del mismo edificio, de muchos a uno (858 filas comparten así su última EUI). Cada unión conserva filas y edificios (`resultados/uniones.csv`).

\begin{figure}[!htb]

{\centering \includegraphics[width=1\linewidth]{resultados/fig1_construccion_muestra} 

}

\caption{Construcción de la muestra en desarrollo (izquierda) y prueba (derecha), en filas edificio–año y edificios. En azul, los objetivos válidos; en naranja, las filas evaluadas, separadas según la historia disponible al predecir. Las filas que solo tienen historia anterior a $a-2$ pasan de 75 en desarrollo a 631 en prueba, lo que explica buena parte de los resultados de la sección 5.2.}\label{fig:fig-muestra}
\end{figure}

## Calidad de los datos

Primero revisamos si las características de cada edificio cambian de un año a otro. De las 44 columnas que no son clave, 21 tienen exactamente el mismo valor en todos los años de un mismo edificio (2015–2022), entre ellas el tipo, el año de construcción, los pisos, las superficies, el barrio y las coordenadas. Esto indica que la base no guarda cómo era el edificio en cada año, sino que repite su valor actual. Usamos estas variables suponiendo que esas características no cambiaron en el período. Por otro lado, el uso principal sí cambia en 331 edificios, por lo que para predecir el año $a$ usamos el uso del último registro hasta $a-2$. También comprobamos que ningún edificio aparece con dos identificadores distintos (Anexo A.4).

Hay 66 filas con 0 pisos y 284 con 0 edificios, las cuales tratamos como dato faltante. Como medida de tamaño usamos la superficie confirmada por la ciudad, siempre positiva e igual a la de los edificios más el estacionamiento, y no la autodeclarada, que difiere en más de 10 % en 1034 edificios. En el entrenamiento final, 33 de las 61 categorías de uso principal tienen menos de 30 filas y se agrupan en «Otro» (2,1 % de las filas).

Para separar errores de registro de consumos extremos válidos fijamos, antes de ajustar modelos, una regla que solo mira años anteriores. Un registro es error si su EUI supera 10 veces la mediana de las EUI previas del mismo edificio y además supera 1000 kBtu/pie², como ocurre con un error de unidades. La regla marca 9 registros en 2015–2022 (por ejemplo, 42 480 con una mediana previa de 23,5; Anexo A.5) y 5 en 2023–2024, que no se usan como objetivo ni como historia. Las caídas no se marcan, porque un edificio puede vaciarse, y los consumos altos con una historia coherente se conservan, por ejemplo, el mayor valor de desarrollo, 1538 kBtu/pie², es de un centro de datos que reportaba 1167 dos años antes.

## Descripción de la respuesta

Antes de modelar, describimos la respuesta en las 16 650 filas de desarrollo que quedan tras excluir los errores de registro (Tabla 1). Su distribución es muy asimétrica, pues la mediana es 37,2 kBtu/pie², pero el percentil 99 llega a 283 y el máximo a 1538. Por lo anterior, se decidió realizar la transformación a log(EUI). Como todos los valores son positivos (mínimo 0,1), el logaritmo está definido, y con él la asimetría baja de 7,3 a −0,1. Además, en escala log una diferencia equivale a un cambio proporcional (una diferencia de 0,1 corresponde aproximadamente a un 10 %), lo que facilita su interpretación.

Otro hallazgo es que la mayor parte de la variación está entre edificios y no dentro de un mismo edificio: la media de cada edificio explica el 86,5 % de la variación de log(EUI) en 2015–2022. Además, la EUI de un edificio se parece mucho a la que tenía dos años antes, como muestra la correlación de Spearman entre ambas, que va de 0,91 en 2017 a 0,85 en 2021. Por eso, la historia del propio edificio es el predictor principal.

Por último, el cambio respecto de $a-2$ crece con el nivel del edificio si se mide en kBtu/pie² (correlación de Spearman entre nivel y cambio absoluto: 0,47), pero casi no depende de él si se mide en log (0,07). Es decir, los edificios cambian en proporción a su consumo, lo que respalda modelar la EUI en escala logarítmica (Anexo A.3). El análisis de sensibilidad S1, que repite la búsqueda de modelos sin el logaritmo, lo confirma (sección 5.4). Las predicciones se devuelven a kBtu/pie² con la función exponencial (sección 4.1).

## Variables admisibles y excluidas

La Tabla 2 resume qué columnas pueden usarse al predecir. El criterio es que solo entra información conocida dos años antes del año objetivo. Se excluyen las columnas que contienen la respuesta, las que se registran después y las que solo identifican al edificio o repiten otra variable.

\begin{table}[!htb]

\caption{\label{tab:tabla-variables}Variables usadas y excluidas, agrupadas por decisión. «Valor actual»: la base repite en todos los años el valor vigente del edificio (Anexo A.4).}
\centering\footnotesize\setlength{\tabcolsep}{4pt}
\begin{tabular}[t]{>{\raggedright\arraybackslash}p{3.6cm}>{\raggedright\arraybackslash}p{6.0cm}>{\raggedright\arraybackslash}p{6.4cm}}
\toprule
Grupo & Columnas & Cómo entran o por qué se excluyen\\
\midrule
Usadas: características del edificio & Barrio, tipo, año de construcción, pisos, edificios de la propiedad, superficie total y de estacionamiento & Valor actual. Entran como barrio, tipo, antigüedad, log de pisos, log de edificios, log de la superficie y fracción de estacionamiento.\\
Usadas: usos del edificio & Usos 1.º a 3.º y sus superficies & Último registro $\leq a-2$. Entran como uso principal, fracción de superficie de ese uso y número de usos.\\
Usadas: historia de la respuesta & EUI de los años $\leq a-2$ & Log de la última EUI válida y de la EUI de $a-3$, con indicadoras.\\
\midrule
Excluidas por fuga & 13 medidas del año objetivo: consumo, emisiones y ENERGY STAR & Contienen la respuesta; sus valores pasados repetirían la historia de la EUI.\\
Excluidas por conocerse después & Distrito del concejo, cumplimiento del reporte y demolición & Usan límites de 2023, el cierre del reporte o el ciclo 2023.\\
Excluidas por identificar o repetir & Identificador y año (clave edificio–año), nombre, dirección, parcela y coordenadas; superficie de edificios y superficies autodeclaradas; tipo de propiedad EPA & Identifican al edificio (la ubicación entra como barrio) o repiten otra variable (sección 2.5).\\
\bottomrule
\end{tabular}
\end{table}

# Diseño de evaluación

## Particiones temporales

Como el objetivo es predecir años futuros de edificios ya conocidos, la partición debe entrenar con el pasado y validar después (EYP3407, 2026, sesión S03; Hyndman y Athanasopoulos, 2021). Usamos tres ventanas que crecen y validan 2019, 2020 y 2021 (Figura 2). Para validar el año $a$ solo se entrena con objetivos hasta $a-2$, porque las respuestas de $a-1$ tampoco estarían disponibles al predecir. Un mismo edificio aparece en entrenamiento y en validación, tal como ocurrirá al usar el modelo. Para medir cuánto ayuda eso, el análisis de sensibilidad S2 (sección 5.4) saca del entrenamiento un 20 % de los edificios y los evalúa como si fueran nuevos. Después de elegir, el procedimiento se reajusta con los objetivos 2017–2021 y se evalúa una sola vez en 2023 y 2024.

\begin{figure}[!htb]

{\centering \includegraphics[width=1\linewidth]{resultados/fig2_diseno_temporal} 

}

\caption{Diseño temporal de la evaluación. Cada fila es un ajuste y cada casilla, un año del reporte. En el ajuste final, 2022 solo aporta historia para predecir 2024.}\label{fig:fig-diseno}
\end{figure}

## Información disponible

Cada predictor se construye con registros de años $\leq a-2$, tanto en las filas evaluadas como en las de entrenamiento, y el código se detiene si alguna variable de historia viene de un año posterior. Además, hicimos una prueba de fuga (`verificacion/fuga.R`): cambiamos al azar la EUI y los usos de los años posteriores a cada corte y volvimos a predecir. Si el código usara información del futuro, las predicciones habrían cambiado, pero no cambió ninguna, ni en las 35 configuraciones ni en la referencia ni en la prueba. Si la ciudad corrigió reportes antiguos después de entregarlos, nuestra base es más limpia que la disponible en su momento y la evaluación resulta algo optimista.

## Métricas, referencia y regla de selección

La métrica principal es el MAE en kBtu/pie², calculado sobre las filas reunidas de las tres ventanas, y el RMSE se informa como complemento porque es sensible a pocos errores grandes. Como un mismo edificio aparece varios años, en prueba también informamos el MAE por edificio, en que cada edificio pesa lo mismo, y el error dividido por la mediana de su tipo, para comparar tipos con niveles de consumo distintos. Todos los procedimientos se evalúan en las mismas filas.

La referencia es predecir con la EUI de $a-2$ o, si ese año falta, con la mediana del tipo en el entrenamiento. Para los casos en que falta $a-2$ pero hay años anteriores, antes de abrir la prueba fijamos también una referencia alternativa que usa la última EUI válida hasta $a-2$. La informamos como comparación, pero no interviene en la selección. Para elegir el procedimiento, dentro de cada familia y entre familias, usamos el menor MAE reunido.

## Congelamiento e incertidumbre

Antes de evaluar la prueba registramos en `CONGELADO.md` la población, la regla de calidad, las variables, los modelos, la búsqueda, la métrica, la regla de selección y el procedimiento elegido, con fecha y huella md5 del código. Para la incertidumbre remuestreamos edificios con reposición (2000 réplicas; EYP3407, 2026, sesión S03; Davison y Hinkley, 1997), de modo que cada edificio aporta todas sus filas a la vez y se respeta la dependencia entre sus años. Como las predicciones quedan fijas, el intervalo de percentiles 95 % de la diferencia de MAE es condicional a los ajustes y no incluye la variación por choques comunes a un año, que examinamos comparando años (sección 5.3). La dispersión entre ventanas no se interpreta como un intervalo, porque las ventanas comparten datos.

# Métodos

## Preprocesamiento común

Todo lo que se estima en la preparación (medianas, categorías agrupadas, escalas) se calcula con el entrenamiento de cada ventana y se aplica sin recalcular a validación y prueba, para evitar fuga de información (EYP3407, 2026, sesión S02).

- **Respuesta:** log(EUI).
- **Historia:** log de la última EUI válida hasta $a-2$ (si no hay, la mediana del entrenamiento, con indicadora), indicadora de historia antigua y log de la EUI de $a-3$ (si falta, se repite la última, con indicadora).
- **Uso** (último registro $\leq a-2$): uso principal, fracción de superficie del uso principal y número de usos, con indicadora de faltante.
- **Edificio:** log de la superficie, fracción de estacionamiento, antigüedad, log de pisos, log del número de edificios, tipo y barrio.
- **Categorías:** las de menos de 30 filas de entrenamiento pasan a «Otro»; un valor ausente, a «Sin dato».

Son 16 predictores, que suman en promedio 49 columnas al convertir las variables categóricas en indicadoras. Los modelos se ajustan sobre log(EUI) y predicen con exp(). Si el residuo en log tiene mediana 0, exp() de la predicción es la mediana condicional de la EUI, que es justamente la predicción que minimiza el error absoluto esperado y, por tanto, la que corresponde al MAE. Este supuesto se revisa en la sección 5.1.

## Procedimientos y expectativas

Comparamos tres familias vistas en el curso, de flexibilidad creciente (EYP3407, 2026, sesiones S11, S14, S15, S16 y S22; James et al., 2021). Las expectativas se escribieron antes de ajustar:

- **M1, lasso** (Tibshirani, 1996; glmnet, Friedman et al., 2010): persistencia en escala log, porque la historia entra de forma lineal, más ajustes aditivos por tipo, uso, tamaño y barrio, con selección de variables por la penalización. Puede fallar si los efectos no son lineales en log o si cambian según el tipo.
- **M2, GAM** (Wood, 2017; mgcv): agrega curvas suaves para la historia, el tamaño y la antigüedad, con suavidad elegida por REML (Wood, 2011). No captura interacciones, y la historia de $a-2$ y la de $a-3$ juntas pueden generar concurvidad.
- **M3, bosque aleatorio** (Breiman, 2001; ranger, Wright y Ziegler, 2017): capta interacciones, como tipo × historia, sin especificarlas. No extrapola fuera del rango visto y puede apoyarse en reconocer edificios ya vistos.

## Búsqueda de hiperparámetros y costo

Para el lasso probamos 20 valores de $\lambda$ en escala logarítmica, desde el que anula todos los coeficientes (0,6019) hasta su milésima parte (EYP3407, 2026, sesión S12). Para el GAM, tres fórmulas de complejidad creciente: G1 solo tiene una curva para la historia, las indicadoras de historia y el tipo; G2 agrega curvas para superficie y antigüedad y las variables de uso, barrio, estacionamiento y pisos; G3 agrega una curva para la EUI de $a-3$ y los predictores restantes (fracción del uso principal, número de usos y número de edificios). Para el bosque, 300 árboles con `mtry` en {3, 5, 8, 12} y tamaño mínimo de nodo en {5, 20, 50}. En total son 35 configuraciones (20 del lasso, 3 del GAM y 12 del bosque), sin superar el máximo de 20 por familia que fija el enunciado, y cada una se evalúa en las tres ventanas (Anexo A.1). Con un núcleo, la búsqueda tomó 117 s para el bosque, 40 s para el GAM y menos de 1 s para el lasso.

# Resultados

## Desarrollo: validación en 2019–2021

\begin{table}[!htb]

\caption{\label{tab:tabla-desarrollo}Comparación en desarrollo: 10 035 filas de validación (2019–2021), las mismas para todos. MAE y RMSE en kBtu/pie². La referencia predice la EUI de $a-2$ (si falta, la mediana del tipo). «Dif.» es el MAE del procedimiento menos el de la referencia, reunido y por ventana; el intervalo remuestrea edificios con predicciones fijas.}
\centering\small\setlength{\tabcolsep}{5pt}
\begin{tabular}[t]{llrrrrrrr}
\toprule
Procedimiento & Configuración & MAE & RMSE & Dif. & IC 95 \% & Dif. 2019 & Dif. 2020 & Dif. 2021\\
\midrule
Referencia & — & 10,44 & 24,0 & — & — & — & — & —\\
Lasso (elegido) & $\lambda$ = 0,005332 & 10,50 & 24,7 & +0,06 & {}[−0,19; 0,35] & +0,95 & −0,61 & −0,16\\
GAM & G1 & 10,52 & 24,5 & +0,08 & {}[−0,10; 0,28] & +0,88 & −0,23 & −0,44\\
Bosque & mtry 5, nodo 5 & 10,52 & 24,6 & +0,08 & {}[−0,14; 0,32] & +0,50 & −0,18 & −0,07\\
\bottomrule
\end{tabular}
\end{table}

En desarrollo ningún procedimiento superó a la referencia (Tabla 3). El lasso tuvo el menor MAE de los tres y quedó 0,06 kBtu/pie² por encima de la referencia, con un intervalo que incluye el 0 ([−0,19; 0,35]). La diferencia cambia de signo según la ventana, pues los tres modelos pierden en 2019, y el lasso gana en 2020 y 2021. Además, los tres modelos quedan muy cerca entre sí (MAE entre 10,50 y 10,52), mucho más cerca que la variación entre ventanas, así que el orden entre familias es frágil. El lasso también es el más simple y barato, este conserva en promedio 23 de 49 coeficientes, frente a 16,6 grados de libertad efectivos del GAM y 300 árboles del bosque.

En cuanto a los supuestos, la mediana del residuo en log es prácticamente 0 dentro del entrenamiento (entre 0,003 y 0,012), así que exp() entrega la mediana condicional. Fuera de la muestra la mediana es negativa, es decir, los modelos sobrestiman cuando todo un año baja. Por ejemplo, la mediana del cambio de log(EUI) respecto de $a-2$ fue +0,060 en 2017, el único año de entrenamiento de la primera ventana, y −0,047 en 2019, el año que valida. El error absoluto en log se mantiene casi constante entre quintiles del nivel predicho (mediana entre 0,09 y 0,14), lo que confirma que el error es aproximadamente proporcional al nivel. En el GAM, la prueba de dimensión de base no indica falta de flexibilidad (valor p 0,85) y la concurvidad de la curva de historia es baja (0,30 en el peor caso). Los residuos por ventana están en el Anexo A.6.

## Prueba: evaluación única en 2023–2024

\begin{table}[!htb]

\caption{\label{tab:tabla-prueba}Comparación en prueba: 7001 filas de 3638 edificios (3496 en 2023 y 3505 en 2024), las mismas para todos. MAE y RMSE en kBtu/pie². «Dif.» es la diferencia de MAE con la referencia de la ficha; el intervalo remuestrea edificios con predicciones fijas. GAM y bosque se informan, pero no se usaron para elegir.}
\centering\small
\begin{tabular}[t]{lrrrrrr}
\toprule
Procedimiento & MAE & RMSE & Dif. MAE & IC 95 \% & MAE 2023 & MAE 2024\\
\midrule
Referencia: EUI de $a-2$ & 10,69 & 28,2 & — & — & 10,44 & 10,95\\
Ref. alternativa: última EUI & 10,01 & 24,3 & −0,69 & — & 9,73 & 10,28\\
Lasso (elegido) & 9,86 & 26,3 & −0,84 & {}[−1,40; −0,23] & 9,87 & 9,84\\
GAM G1 & 9,84 & 23,9 & −0,85 & {}[−1,25; −0,48] & 9,97 & 9,71\\
Bosque & 9,50 & 22,7 & −1,19 & {}[−1,73; −0,67] & 9,49 & 9,51\\
\bottomrule
\end{tabular}
\end{table}

En la prueba, el lasso tuvo un MAE de 9,86 kBtu/pie², 0,84 menos que la referencia de la ficha, con intervalo [−1,40; −0,23] (Tabla 4). La ventaja fue mayor en 2024 (−1,11) que en 2023 (−0,57, con un intervalo que incluye el 0). El GAM y el bosque también superaron a la referencia, y el bosque obtuvo el menor MAE (9,50). Sin embargo, cambiar de procedimiento después de ver la prueba invalidaría la evaluación, por lo que se mantiene el lasso. Su RMSE (26,3) es menor que el de la referencia, pero mayor que el de la referencia alternativa, porque comete algunos errores muy grandes (sección 5.3).

\begin{table}[!htb]

\caption{\label{tab:tabla-historia}MAE en prueba (kBtu/pie²) según la historia disponible. El aporte es la diferencia de MAE del lasso con la referencia en el grupo, ponderada por su fracción de filas; los tres aportes suman −0,839.}
\centering\small
\begin{tabular}[t]{lrrrrrrr}
\toprule
Historia disponible & n & Ref. & Ref. alt. & Lasso & GAM & Bosque & Aporte a la dif. del lasso\\
\midrule
EUI en $a-2$ & 6115 & 9,20 & 9,20 & 9,08 & 9,05 & 8,64 & −0,106\\
Solo historia anterior a $a-2$ & 631 & 22,77 & 15,13 & 15,16 & 15,30 & 15,46 & −0,686\\
Sin historia & 255 & 16,62 & 16,62 & 15,32 & 15,34 & 15,46 & −0,047\\
\bottomrule
\end{tabular}
\end{table}

¿Por qué el lasso gana en prueba y no en desarrollo? La Tabla 5 separa las filas según la historia disponible. Cuando existe la EUI de $a-2$, la ventaja del lasso es pequeña (9,08 frente a 9,20). La diferencia está en las 631 filas que solo tienen historia más antigua: ahí la referencia de la ficha usa la mediana del tipo y llega a un MAE de 22,77, mientras el lasso, que usa la última EUI, baja a 15,16. Esas filas explican 0,69 de los 0,84 de ventaja, y en desarrollo eran apenas 75. La referencia alternativa, que también usa la última EUI, logra 15,13 en ese grupo. Frente a ella, el lasso gana solo 0,15 en total, con un intervalo que incluye el 0 y un signo que cambia entre años. Sin historia, el lasso mejora a la mediana del tipo en 1,3 kBtu/pie².

## Análisis de errores

El error cambia más entre años que entre procedimientos (Figura 3A). Todos alcanzan su mayor MAE en 2021, y la ventaja del lasso cambia de signo de un año a otro. La Figura 3B explica la razón, en 2020 y 2021 los cambios de cada edificio respecto de $a-2$ fueron los más dispersos del período, con rangos intercuartiles de 0,23 y 0,21 en log, frente a 0,14–0,16 en los demás años. La pandemia afectó sobre todo a los edificios no residenciales, cuya EUI bajó en mediana un 13 % en 2020, mientras la de los multifamiliares de 5 a 9 pisos no cambió (Anexo A.7). Un choque así hace que el desempeño de un año no garantice el del siguiente.

\begin{figure}[!htb]

{\centering \includegraphics[width=1\linewidth]{resultados/fig3_error_y_cambio_por_anio} 

}

\caption{Error por año y choques comunes. A: MAE (kBtu/pie²) del lasso y de las dos referencias en cada año evaluado. B: mediana (punto) y rango intercuartil (barra) del cambio log(EUI de $a$ / EUI de $a-2$) en los edificios con ambos valores.}\label{fig:fig-anios}
\end{figure}

Por subgrupos (Tabla 6), el lasso mejora a la referencia alternativa en multifamiliares y escuelas, pero es peor en hospitales (+2,1), edificios no residenciales (+1,1) y universidades (+6,9, con solo 69 filas). Según el tamaño, es mejor en los tres quintiles menores de superficie y peor en los dos mayores. Por uso principal (Anexo A.8), gana en vivienda multifamiliar, bodegas, escuelas y lugares de culto, empata en oficinas y pierde en hoteles, comercio y usos poco frecuentes.

\begin{table}[!htb]

\caption{\label{tab:tabla-subgrupos}MAE en prueba (kBtu/pie²) del lasso y de la referencia alternativa, por tipo de edificio y por quintil de superficie (pie², cortes del entrenamiento final). Ambos se evalúan en las mismas filas de cada grupo; una diferencia negativa indica que el lasso erra menos.}
\centering\small
\begin{tabular}[t]{lrrrr}
\toprule
Grupo & n & Ref. alt. & Lasso & Diferencia (lasso − ref. alt.)\\
\midrule
\multicolumn{5}{l}{\textbf{Por tipo de edificio}}\\
Escuela & 284 & 9,23 & 6,31 & −2,92\\
Multifamiliar, 1 a 4 pisos & 2054 & 7,43 & 6,03 & −1,40\\
Multifamiliar, 5 a 9 pisos & 1572 & 5,89 & 5,38 & −0,51\\
Multifamiliar, 10 o más pisos & 284 & 8,09 & 7,64 & −0,45\\
No residencial & 2644 & 14,27 & 15,37 & +1,10\\
Hospital & 94 & 16,47 & 18,61 & +2,15\\
Universidad & 69 & 19,30 & 26,20 & +6,90\\
\midrule
\multicolumn{5}{l}{\textbf{Por quintil de superficie}}\\
Q1 (< 26 964) & 1293 & 10,31 & 10,08 & −0,22\\
Q2 (26 964–38 630) & 1384 & 10,84 & 9,81 & −1,03\\
Q3 (38 630–60 375) & 1377 & 9,77 & 9,16 & −0,61\\
Q4 (60 375–125 607) & 1432 & 9,49 & 10,00 & +0,51\\
Q5 (≥ 125 607) & 1515 & 9,69 & 10,19 & +0,50\\
\bottomrule
\end{tabular}
\end{table}

El lasso no es confiable en los edificios de consumo muy alto. Los puntos negros de la Figura 4 son las 62 filas cuya última EUI supera 283 kBtu/pie², el percentil 99 del entrenamiento. La mayoría queda sobre la línea discontinua, es decir, la EUI observada es mayor que la predicha: en mediana, el lasso predice 27,4 kBtu/pie² menos de lo observado. En ese grupo su MAE es 113,2, frente a 89,8 de la referencia alternativa, mientras que en el resto de las filas el lasso es mejor (8,93 frente a 9,29).

La subestimación se debe a que, en el lasso final, los coeficientes de la historia suman 0,86 en escala log, y no 1. Por eso la predicción no sigue a la historia en la misma proporción, sino que la acerca al centro de la distribución, si un edificio consumía el doble que otro, el modelo predice que consumirá unas 1,8 veces más (2 elevado a 0,86). En los consumos más altos, ese recorte se nota más. Estos pocos edificios también explican el RMSE: el 1 % de las filas con mayor error concentra el 70 % del error cuadrático del lasso (Anexo A.9).

\begin{figure}[!htb]

{\centering \includegraphics{resultados/fig4_observado_vs_predicho_prueba} 

}

\caption{EUI observada frente a predicha por el lasso en la prueba, en escala logarítmica (kBtu/pie²). En negro, las 62 filas cuya última EUI supera el percentil 99 del entrenamiento (283 kBtu/pie²); la línea discontinua marca predicción igual a observación. Los puntos sobre la línea son filas en que el modelo predijo menos de lo observado.}\label{fig:fig-extremos}
\end{figure}

Si cada edificio pesa lo mismo, el orden se mantiene: el MAE por edificio es 10,08 para el lasso, 10,28 para la referencia alternativa y 10,98 para la de la ficha. En términos relativos, el error típico del lasso equivale a 23 % de la mediana de su tipo.

## Sensibilidades

\begin{table}[!htb]

\caption{\label{tab:tabla-sensibilidad}Sensibilidades en desarrollo (10 035 filas de validación; MAE en kBtu/pie²). S1 repite la búsqueda sin transformar la respuesta. S2 saca de todos los entrenamientos el 20 \% de los edificios y muestra el cambio del MAE en esos edificios y en los demás. La última columna rehace la base sin la regla de errores de registro y evalúa en las mismas filas válidas.}
\centering\small
\begin{tabular}[t]{l>{\raggedleft\arraybackslash}p{2.3cm}>{\raggedleft\arraybackslash}p{2.3cm}>{\raggedleft\arraybackslash}p{2.3cm}>{\raggedleft\arraybackslash}p{2.3cm}>{\raggedleft\arraybackslash}p{2.3cm}}
\toprule
Procedimiento & MAE base (log) & S1: MAE en escala original & S2: cambio, excluidos & S2: cambio, incluidos & Sin regla: MAE, mismas filas\\
\midrule
Referencia & 10,44 & — & +0,01 & 0,00 & 12,18\\
Lasso & 10,50 & 11,23 & +0,14 & +0,05 & 10,74\\
GAM & 10,52 & 11,42 & +0,29 & +0,06 & 11,74\\
Bosque & 10,52 & 11,27 & +0,80 & +0,09 & 10,55\\
\bottomrule
\end{tabular}
\end{table}

**S1, escala de la respuesta (decisión de representación).** Repetimos toda la búsqueda con la EUI y la historia sin logaritmo, con las mismas ventanas, filas y presupuesto (Tabla 7). Notamos que en los tres procedimientos el MAE sube entre 0,7 y 0,9 kBtu/pie², y el GAM G3 llega a producir 2265 predicciones negativas. El RMSE del lasso y del GAM baja levemente, lo esperable al estimar la media condicional en vez de la mediana. De todas formas, se pueden determinar las mismas conclusiones, ya que el lasso sigue siendo el de menor MAE, ningún modelo supera a la referencia, y la escala log es la que corresponde a la métrica principal, como anticipaba la descripción de la sección 2.6.

**S2, edificios nuevos (decisión de validación).** Sacamos de todos los entrenamientos un 20 % de los edificios, elegidos al azar con semilla fija (721 edificios), y comparamos en las mismas filas, en la línea del diagnóstico de sensibilidad de la sesión S17 (EYP3407, 2026). Para esos edificios, el MAE sube 0,14 en el lasso, 0,29 en el GAM y 0,80 en el bosque, y en los demás sube menos de 0,1. El bosque es el que más depende de haber visto al edificio, así que su ventaja en prueba podría no repetirse con edificios nuevos. La conclusión de desarrollo tampoco cambia, ya que el lasso sigue siendo el mejor de los tres y ninguno supera a la referencia. Elegimos esta sensibilidad en vez de quitar el predictor de consumo histórico, como sugiere la ficha, porque la historia es la base de la referencia y de los tres modelos. Además, lo que ocurre sin historia ya se ve en las filas que no la tienen (Tabla 5), donde el MAE en prueba sube a 15,3 kBtu/pie².

**Control de la regla de errores de registro.** Sin la regla, en las mismas filas válidas, el MAE de la referencia sube de 10,44 a 12,18, porque los registros erróneos pasan a ser historia. Es decir, sin la regla unos pocos registros erróneos distorsionan la comparación.

# Discusión

## Respuesta a la pregunta

Con información hasta $a-2$, la EUI anual de un edificio conocido se anticipa con un MAE cercano a 10 kBtu/pie², alrededor de un cuarto del nivel típico de su tipo. Casi toda la información útil está en la historia del propio edificio, como sugería la descripción de los datos: cuando existe la EUI de $a-2$, el lasso apenas mejora a la persistencia, y su ventaja frente a la referencia de la ficha viene de usar la última EUI cuando falta la de $a-2$. Los atributos del edificio ayudan sobre todo cuando no hay historia. Los coeficientes del lasso (Anexo A.2) son asociaciones predictivas; con predictores correlacionados, como superficie, pisos y tipo, no deben leerse como efectos causales.

## Utilidad y condiciones de uso

En desarrollo el lasso no superó a la referencia, y en prueba su ganancia frente a una persistencia bien construida (la referencia alternativa) es de 0,15 kBtu/pie², con un intervalo que incluye el 0. Es una ganancia pequeña e incierta, que por sí sola no justifica la mayor complejidad. Como herramienta para el programa, sugerimos:

- **Con historia:** usar la última EUI reportada hasta $a-2$. El lasso rinde casi igual, pero es más complejo y menos confiable en edificios grandes, hospitales, universidades y consumos extremos.
- **Sin historia:** usar el lasso, que mejora a la mediana del tipo en 1,3 kBtu/pie².
- **Consumo previo extremo** (≥ 283 kBtu/pie²): no usar el lasso, que subestima.
- **Cada año:** reajustar con los nuevos reportes y revisar si hubo un choque común, que ningún modelo entrenado con años anteriores puede anticipar.

Estas sugerencias se basan en comparaciones definidas antes de abrir la prueba, pero en solo dos años, así que conviene confirmarlas con años nuevos.

## Límites de generalización

El estudio tiene cuatro límites principales. Primero, la evaluación es retrospectiva: usamos la base descargada en 2026, en la que la ciudad pudo corregir reportes antiguos, y algunos atributos aparecen con su valor actual en todos los años; ambas cosas pueden hacer que los resultados sean algo optimistas. Segundo, las conclusiones valen solo para edificios que reportan en el año objetivo: no sabemos cuánto sería el error en los que no reportaron, y en los edificios sin historia el error es mucho mayor (MAE de 15,3 en prueba). Tercero, la prueba cubre solo dos años, ambos posteriores a la pandemia, y los intervalos no incluyen la variación entre años, que en desarrollo llegó a cambiar el signo de las diferencias. Por último, los umbrales de la regla de errores de registro los fijó el equipo y no provienen de una norma externa, en el control de la sección 5.4 muestra qué ocurre si no se aplica la regla.

## Errores detectados y su corrección

- **Regla de selección con ventanas dependientes.** El plan inicial usaba la regla de un error estándar (EYP3407, 2026, sesión S03), con el error estándar calculado a partir de los tres MAE por ventana. Como las ventanas comparten edificios y datos, y los choques por año inflan esa dispersión, la regla elegía un lasso mucho más penalizado ($\lambda$ = 0,03284, MAE 10,94). Por eso, antes de abrir la prueba, cambiamos la regla y elegimos simplemente el menor MAE reunido (EYP3407, 2026, sesión S10 y enunciado 4.3). Con este cambio, el lasso elegido pasó a $\lambda$ = 0,005332.
- **Orden de categorías dependiente del idioma.** Para usar una variable categórica, el lasso la convierte en indicadoras y deja una categoría como base. R elige esa base por orden alfabético, y ese orden cambia según la configuración de idioma del computador (por ejemplo, en cómo ordena tildes y mayúsculas). Como la penalización del lasso depende de cuál es la base, en otro computador el ajuste podía cambiar levemente. Lo detectamos después de evaluar la prueba y fijamos el orden en `analisis.R`. Al repetir el análisis, todas las tablas y predicciones salieron idénticas, así que los resultados no cambiaron.
- **Fuga, prueba y duplicados.** Ninguna verificación encontró fuga (sección 3.2), la prueba se evaluó una sola vez con decisiones congeladas, la clave edificio–año es única y cada exclusión está documentada.

# Reproducibilidad y contribuciones



- **Comando:** `Rscript --vanilla analisis.R`, desde la raíz del repositorio y con el paquete de datos descomprimido en `datos/`. Ejecuta la preparación, las particiones, el ajuste, la evaluación, las figuras y este informe.
- **Versión del repositorio:** commit `c89e063` (con cambios sin confirmar en el código). Enlace: <https://github.com/JuanPabloCuevas/Proyecto-EYP3407-Grupo-4>.
- **Entradas:** `caso04_seattle_edificios.zip`, descomprimido en `datos/` con sus tres archivos: `datos.csv`, `diccionario.csv` y `LEEME.txt`.
- **Huella de la entrada:** md5 de `datos.csv`, bc623281c6ad5a50017d5f0d8e2a3b1a.
- **Entorno y tiempo:** R 4.5.3 (R Core Team, 2026) en Windows 11 x64 (build 26200), 12 núcleos; el análisis tomó 6,0 minutos, más la generación de este informe. Paquetes: dplyr 1.2.1, glmnet sin dato, mgcv 1.9-4, ranger sin dato, rmarkdown 2.31, knitr 1.51. Semilla 3407 para el bosque, el remuestreo y la muestra de S2; los modelos usan un núcleo.
- **Salidas:** tablas, predicciones y figuras en `resultados/`; las decisiones congeladas antes de la prueba y su registro de cambios, en `CONGELADO.md`; la prueba desde una copia limpia, en `README.md`.
- **Contribuciones:** Maximiliano León coordinó el análisis final y preparó el repositorio; Juan Pablo Cuevas desarrolló un análisis paralelo para contrastarlo, hizo la prueba de reproducción y elaboró la presentación; Cristóbal Honorato auditó y preparó los datos, construyó la base analítica y definió las particiones; Michelle Houngbo definió las sensibilidades y colaboró en la redacción del informe y en la presentación. Detalle en `README.md`.
- **Declaración de uso de IA:** Maximiliano León, Juan Pablo Cuevas y Cristóbal Honorato usaron Claude (Anthropic), y Michelle Houngbo otra herramienta de IA, como apoyo en programación, depuración y redacción. Las cifras del informe se verifican contra los resultados al compilar, y el análisis se reprodujo desde una copia limpia y en otro computador. Herramienta, fechas, propósito y partes afectadas de cada integrante, en `README.md`.

\newpage

# Referencias {-}

Breiman, L. (2001). Random forests. *Machine Learning*, 45(1), 5–32.

City of Seattle, Office of Sustainability and Environment (2026). *Building Energy Benchmarking Data, 2015-Present* [conjunto de datos `teqw-tu6e`, dominio público]. Portal de datos abiertos de Seattle, <https://data.seattle.gov>. Copia con los registros 2015–2024 preparada para el curso el 12 de octubre de 2026.

Davison, A. C. y Hinkley, D. V. (1997). *Bootstrap Methods and their Application*. Cambridge University Press.

EYP3407 (2026). *Proyecto aplicado: enunciado, ficha del caso 04 y rúbrica*; sesiones S02 (*Evaluación de modelos*), S03 (*Remuestreo y validación*), S10 (*Selección de variables*), S11 (*Regularización I*), S12 (*Regularización II: alta dimensión*), S14 (*Regresión no lineal II*), S15 (*Modelos aditivos*), S16 (*Árboles*), S17 (*Poda y validación*) y S22 (*Bagging y bosques aleatorios*). Pontificia Universidad Católica de Chile.

Friedman, J., Hastie, T. y Tibshirani, R. (2010). Regularization paths for generalized linear models via coordinate descent. *Journal of Statistical Software*, 33(1), 1–22.

Hyndman, R. J. y Athanasopoulos, G. (2021). *Forecasting: Principles and Practice* (3.ª ed.). OTexts.

James, G., Witten, D., Hastie, T. y Tibshirani, R. (2021). *An Introduction to Statistical Learning with Applications in R* (2.ª ed.). Springer.

R Core Team (2026). *R: A Language and Environment for Statistical Computing*. R Foundation for Statistical Computing, Viena.

Tibshirani, R. (1996). Regression shrinkage and selection via the lasso. *Journal of the Royal Statistical Society: Series B*, 58(1), 267–288.

Wood, S. N. (2011). Fast stable restricted maximum likelihood and marginal likelihood estimation of semiparametric generalized linear models. *Journal of the Royal Statistical Society: Series B*, 73(1), 3–36.

Wood, S. N. (2017). *Generalized Additive Models: An Introduction with R* (2.ª ed.). Chapman and Hall/CRC.

Wright, M. N. y Ziegler, A. (2017). ranger: A fast implementation of random forests for high dimensional data in C++ and R. *Journal of Statistical Software*, 77(1), 1–17.

\newpage
\appendix

# Anexo técnico

## Búsqueda completa en desarrollo

\begin{table}[H]

\caption{\label{tab:anexo-busqueda}Las 35 configuraciones evaluadas en las tres ventanas (10 035 filas). MAE y RMSE reunidos en kBtu/pie². Lasso en orden de penalización decreciente; GAM de G1 a G3; bosque ordenado por MAE.}
\centering\small
\begin{tabular}[t]{llrrrrr}
\toprule
Familia & Configuración & MAE & RMSE & MAE 2019 & MAE 2020 & MAE 2021\\
\midrule
Lasso & $\lambda$ = 0,6019 & 25,61 & 55,7 & 26,78 & 23,40 & 26,77\\
Lasso & $\lambda$ = 0,4184 & 20,72 & 49,5 & 21,69 & 18,56 & 22,05\\
Lasso & $\lambda$ = 0,2909 & 17,22 & 43,5 & 17,95 & 15,27 & 18,58\\
Lasso & $\lambda$ = 0,2022 & 14,77 & 38,1 & 15,26 & 13,04 & 16,15\\
Lasso & $\lambda$ = 0,1406 & 13,14 & 33,8 & 13,38 & 11,66 & 14,49\\
Lasso & $\lambda$ = 0,09774 & 12,14 & 30,7 & 12,17 & 10,92 & 13,43\\
Lasso & $\lambda$ = 0,06795 & 11,52 & 28,5 & 11,41 & 10,51 & 12,76\\
Lasso & $\lambda$ = 0,04724 & 11,15 & 27,1 & 10,92 & 10,30 & 12,34\\
Lasso & $\lambda$ = 0,03284 & 10,94 & 26,1 & 10,64 & 10,20 & 12,07\\
Lasso & $\lambda$ = 0,02283 & 10,78 & 25,6 & 10,45 & 10,07 & 11,92\\
Lasso & $\lambda$ = 0,01587 & 10,65 & 25,2 & 10,31 & 9,92 & 11,81\\
Lasso & $\lambda$ = 0,01103 & 10,56 & 24,9 & 10,24 & 9,83 & 11,70\\
Lasso & $\lambda$ = 0,00767 & 10,51 & 24,8 & 10,22 & 9,77 & 11,64\\
Lasso & $\lambda$ = 0,005332 (elegida) & 10,50 & 24,7 & 10,20 & 9,76 & 11,64\\
Lasso & $\lambda$ = 0,003707 & 10,52 & 24,7 & 10,20 & 9,78 & 11,67\\
Lasso & $\lambda$ = 0,002577 & 10,54 & 24,7 & 10,21 & 9,80 & 11,69\\
Lasso & $\lambda$ = 0,001791 & 10,55 & 24,7 & 10,25 & 9,81 & 11,71\\
Lasso & $\lambda$ = 0,001245 & 10,57 & 24,8 & 10,28 & 9,81 & 11,73\\
Lasso & $\lambda$ = 0,0008658 & 10,59 & 24,8 & 10,30 & 9,83 & 11,75\\
Lasso & $\lambda$ = 0,0006019 & 10,61 & 24,8 & 10,32 & 9,85 & 11,75\\
GAM & G1 (elegida) & 10,52 & 24,5 & 10,13 & 10,14 & 11,35\\
GAM & G2 & 10,79 & 24,9 & 10,51 & 10,33 & 11,59\\
GAM & G3 & 10,54 & 24,5 & 10,21 & 9,97 & 11,53\\
Bosque & mtry 5, nodo 5 (elegida) & 10,52 & 24,6 & 9,75 & 10,19 & 11,73\\
Bosque & mtry 8, nodo 5 & 10,55 & 24,2 & 9,80 & 10,21 & 11,74\\
Bosque & mtry 8, nodo 20 & 10,58 & 25,5 & 9,85 & 10,21 & 11,78\\
Bosque & mtry 3, nodo 5 & 10,60 & 25,9 & 9,85 & 10,20 & 11,84\\
Bosque & mtry 5, nodo 20 & 10,62 & 26,6 & 9,90 & 10,25 & 11,82\\
Bosque & mtry 8, nodo 50 & 10,64 & 27,1 & 10,02 & 10,19 & 11,81\\
Bosque & mtry 12, nodo 50 & 10,68 & 26,5 & 10,05 & 10,23 & 11,86\\
Bosque & mtry 12, nodo 20 & 10,69 & 25,5 & 9,92 & 10,31 & 11,92\\
Bosque & mtry 12, nodo 5 & 10,69 & 24,3 & 9,96 & 10,31 & 11,90\\
Bosque & mtry 5, nodo 50 & 10,73 & 28,7 & 10,09 & 10,37 & 11,81\\
Bosque & mtry 3, nodo 20 & 10,82 & 28,8 & 10,20 & 10,44 & 11,90\\
Bosque & mtry 3, nodo 50 & 11,17 & 31,5 & 10,60 & 10,76 & 12,23\\
\bottomrule
\end{tabular}
\end{table}

## Coeficientes del lasso final

\begin{table}[H]

\caption{\label{tab:anexo-coeficientes}Coeficientes distintos de 0 del lasso ajustado con los objetivos 2017–2021 ($\lambda$ = 0,005332), en escala de log(EUI) y en las unidades originales de cada predictor (glmnet estandariza los predictores para penalizar, pero entrega los coeficientes en sus unidades). Cada indicadora de categoría se compara con la categoría base de su variable. Son asociaciones predictivas, no efectos causales.}
\centering\footnotesize
\begin{tabular}[t]{lrlr}
\toprule
Variable & Coeficiente & Variable  & Coeficiente \\
\midrule
Constante & 0,462 & Uso: Office & −0,0003\\
log(última EUI válida hasta $a-2$) & 0,674 & Uso: Other & 0,012\\
log(EUI de $a-3$) & 0,187 & Uso: Otro & 0,057\\
Falta la EUI de $a-3$ & 0,079 & Uso: Self-Storage Facility & −0,100\\
log(superficie) & 0,001 & Uso: Senior Living Community & 0,012\\
Fracción de estacionamiento & 0,018 & Uso: Sin dato & −0,142\\
log(número de edificios) & 0,005 & Uso: Supermarket/Grocery Store & 0,162\\
Tipo: University & 0,071 & Uso: Vehicle Repair Services & 0,020\\
Uso: Distribution Center & −0,015 & Barrio: EAST & 0,011\\
Uso: Hospital (General Medical \& Surgical) & 0,224 & Barrio: GREATER DUWAMISH & −0,001\\
Uso: Hotel & −0,004 & Barrio: LAKE UNION & 0,017\\
Uso: K-12 School & 0,008 & Barrio: MAGNOLIA / QUEEN ANNE & −0,0004\\
Uso: Laboratory & 0,209 & Barrio: NORTH & −0,018\\
Uso: Medical Office & 0,086 & Barrio: NORTHEAST & 0,005\\
Uso: Non-Refrigerated Warehouse & −0,015 &  & \\
\bottomrule
\end{tabular}
\end{table}

## Datos por año y descripción de la respuesta

\begin{table}[H]

\caption{\label{tab:anexo-anios}Registros por año, respuestas faltantes, altas y bajas de edificios respecto del año anterior (2015–2022, sin mirar la prueba) y filas objetivo válidas según la historia disponible (2017–2021 y 2023–2024).}
\centering\small
\begin{tabular}[t]{lrrrrrrr}
\toprule
Año & Filas & Sin respuesta & Altas & Bajas & Objetivo: EUI en $a-2$ & Solo historia anterior & Sin historia\\
\midrule
2015 & 3175 & 33 & — & — & — & — & —\\
2016 & 3253 & 45 & 84 & 6 & — & — & —\\
2017 & 3310 & 37 & 61 & 4 & 3109 & 0 & 164\\
2018 & 3381 & 39 & 84 & 13 & 3166 & 12 & 164\\
2019 & 3456 & 46 & 89 & 14 & 3214 & 20 & 175\\
2020 & 3530 & 57 & 93 & 19 & 3266 & 25 & 178\\
2021 & 3578 & 419 & 56 & 8 & 3000 & 30 & 127\\
2022 & 3617 & 345 & 50 & 11 & — & — & —\\
2023 & — & — & — & — & 3012 & 361 & 123\\
2024 & — & — & — & — & 3103 & 270 & 132\\
\bottomrule
\end{tabular}
\end{table}

\begin{table}[H]

\caption{\label{tab:anexo-respuesta}Distribución de la respuesta en las 16 650 filas de desarrollo.}
\centering\small
\begin{tabular}[t]{lrrrrrrrr}
\toprule
Escala & Mín. & p1 & p25 & Mediana & p75 & p99 & Máx. & Media\\
\midrule
EUI (kBtu/pie²) & 0,10 & 5,80 & 27,60 & 37,20 & 57,60 & 283,46 & 1538,10 & 52,46\\
log(EUI) & −2,30 & 1,76 & 3,32 & 3,62 & 4,05 & 5,65 & 7,34 & 3,70\\
\bottomrule
\end{tabular}
\end{table}

\begin{table}[H]

\caption{\label{tab:anexo-descriptivas}Persistencia: correlación entre la EUI del año objetivo y la de $a-2$, y mediana del cambio log(EUI de $a$ / EUI de $a-2$), en los objetivos de desarrollo con EUI válida en ambos años.}
\centering\small
\begin{tabular}[t]{lrrrr}
\toprule
Año objetivo & Pares & Spearman & Pearson en log & Mediana del cambio en log\\
\midrule
2017 & 3109 & 0,914 & 0,905 & +0,060\\
2018 & 3166 & 0,903 & 0,903 & −0,007\\
2019 & 3214 & 0,891 & 0,890 & −0,047\\
2020 & 3266 & 0,869 & 0,865 & −0,037\\
2021 & 3000 & 0,853 & 0,829 & −0,015\\
\bottomrule
\end{tabular}
\end{table}

\begin{table}[H]

\caption{\label{tab:anexo-cambio-nivel}Cambio respecto de $a-2$ según el nivel de $a-2$ (deciles, 15 755 pares). El cambio absoluto crece con el nivel; el cambio en log, no (Spearman entre nivel y cambio absoluto: 0,47 en kBtu/pie² y 0,07 en log).}
\centering\small
\begin{tabular}[t]{rrrr}
\toprule
Decil & EUI mediana en $a-2$ & Mediana de |cambio| (kBtu/pie²) & Mediana de |cambio| en log\\
\midrule
1 & 18,4 & 1,9 & 0,121\\
2 & 24,5 & 1,7 & 0,070\\
3 & 28,0 & 1,8 & 0,064\\
4 & 31,5 & 2,1 & 0,068\\
5 & 35,8 & 2,9 & 0,081\\
6 & 41,5 & 3,9 & 0,092\\
7 & 49,1 & 5,1 & 0,103\\
8 & 60,3 & 6,8 & 0,113\\
9 & 78,0 & 8,6 & 0,112\\
10 & 141,1 & 16,4 & 0,105\\
\bottomrule
\end{tabular}
\end{table}

\begin{table}[H]

\caption{\label{tab:anexo-varianza}Fracción de la variación de la EUI de 2015–2022 que explica la media de cada edificio (suma de cuadrados entre edificios sobre la total), por tipo de edificio. Excluye los errores de registro.}
\centering\small
\begin{tabular}[t]{lrrrr}
\toprule
Tipo & Edificios & Filas & Entre edificios, log(EUI) & Entre edificios, EUI\\
\midrule
Hospital & 57 & 412 & 91,6 \% & 90,7 \%\\
Multifamiliar, 10 o más pisos & 136 & 955 & 70,1 \% & 79,0 \%\\
Multifamiliar, 1 a 4 pisos & 1086 & 8092 & 78,8 \% & 69,8 \%\\
Multifamiliar, 5 a 9 pisos & 771 & 5153 & 78,4 \% & 79,3 \%\\
No residencial & 1447 & 10 403 & 87,0 \% & 89,5 \%\\
Escuela & 147 & 1036 & 75,0 \% & 75,1 \%\\
Universidad & 35 & 219 & 89,0 \% & 98,8 \%\\
Todos & 3679 & 26 270 & 86,5 \% & 90,4 \%\\
\bottomrule
\end{tabular}
\end{table}

## Auditoría de columnas

\begin{table}[H]

\caption{\label{tab:anexo-columnas}Columnas no clave en 2015–2022: número de edificios en que el valor cambia entre años (0 indica un valor actual copiado a todos los años) y porcentaje de filas faltantes. Hay 3692 edificios en esos años.}
\centering\footnotesize\setlength{\tabcolsep}{4pt}
\begin{tabular}[t]{lrrlrr}
\toprule
Columna & Cambios & Faltante & Columna  & Cambios  & Faltante \\
\midrule
\texttt{buildingname} & 0 & 0,0 \% & \texttt{siteeui\_kbtu\_sf} & 3627 & 3,7 \%\\
\texttt{buildingtype} & 0 & 0,0 \% & \texttt{siteenergyuse\_kbtu} & 3627 & 3,7 \%\\
\texttt{taxparcelidentificationnumber} & 0 & 0,0 \% & \texttt{siteenergyusewn\_kbtu} & 3624 & 4,8 \%\\
\texttt{address} & 0 & 0,0 \% & \texttt{sourceeuiwn\_kbtu\_sf} & 3623 & 4,8 \%\\
\texttt{city} & 0 & 0,0 \% & \texttt{sourceeui\_kbtu\_sf} & 3627 & 3,7 \%\\
\texttt{state} & 0 & 0,0 \% & \texttt{epapropertytype} & 364 & 0,0 \%\\
\texttt{zipcode} & 0 & 0,0 \% & \texttt{largestpropertyusetype} & 331 & 0,0 \%\\
\texttt{latitude} & 0 & 0,0 \% & \texttt{largestpropertyusetypegfa} & 1613 & 0,0 \%\\
\texttt{longitude} & 0 & 0,0 \% & \texttt{secondlargestpropertyusetype} & 513 & 40,4 \%\\
\texttt{neighborhood} & 0 & 0,0 \% & \texttt{secondlargestpropertyuse} & 879 & 45,5 \%\\
\texttt{councildistrictcode} & 0 & 0,0 \% & \texttt{thirdlargestpropertyusetype} & 384 & 75,4 \%\\
\texttt{yearbuilt} & 0 & 0,0 \% & \texttt{thirdlargestpropertyusetypegfa} & 433 & 78,2 \%\\
\texttt{numberoffloors} & 0 & 0,0 \% & \texttt{electricity\_kwh} & 3627 & 2,9 \%\\
\texttt{numberofbuildings} & 0 & 0,0 \% & \texttt{steamuse\_kbtu} & 136 & 96,5 \%\\
\texttt{propertygfatotal} & 0 & 0,0 \% & \texttt{naturalgas\_therms} & 2484 & 39,1 \%\\
\texttt{propertygfabuildings} & 0 & 0,0 \% & \texttt{compliancestatus} & 1236 & 0,0 \%\\
\texttt{propertygfaparking} & 0 & 0,0 \% & \texttt{complianceissue} & 1230 & 1,7 \%\\
\texttt{selfreportgfatotal} & 0 & 0,0 \% & \texttt{electricity\_kbtu} & 3627 & 2,9 \%\\
\texttt{selfreportgfabuildings} & 0 & 0,0 \% & \texttt{naturalgas\_kbtu} & 2484 & 39,1 \%\\
\texttt{selfreportparking} & 0 & 0,0 \% & \texttt{totalghgemissions} & 3628 & 2,6 \%\\
\texttt{energystarscore} & 2997 & 26,9 \% & \texttt{ghgemissionsintensity} & 3541 & 4,6 \%\\
\texttt{siteeuiwn\_kbtu\_sf} & 3623 & 4,8 \% & \texttt{demolished} & 0 & 0,0 \%\\
\bottomrule
\end{tabular}
\end{table}

## Errores de registro y saltos grandes

\begin{table}[H]

\caption{\label{tab:anexo-errores}Registros de 2015–2022 marcados por la regla (EUI > 10 veces la mediana previa del edificio y > 1000 kBtu/pie²). Otros 18 saltos de más de 10 veces no se marcan porque su nivel es posible.}
\centering\small
\begin{tabular}[t]{rrlrrr}
\toprule
Edificio & Año & Tipo & EUI & Mediana previa & Veces\\
\midrule
50239 & 2021 & Multifamily HR (10+) & 42 480,2 & 23,5 & 1808\\
755 & 2019 & NonResidential & 17 488,5 & 71,8 & 244\\
755 & 2020 & NonResidential & 17 549,6 & 72,9 & 241\\
25042 & 2022 & NonResidential & 6389,5 & 42,8 & 149\\
49967 & 2020 & University & 6702,9 & 116,9 & 57\\
23689 & 2021 & NonResidential & 1952,2 & 40,7 & 48\\
503 & 2020 & NonResidential & 3742,4 & 111,7 & 34\\
23120 & 2022 & NonResidential & 2544,8 & 110,5 & 23\\
27162 & 2020 & NonResidential & 4462,8 & 286,1 & 16\\
\bottomrule
\end{tabular}
\end{table}

## Supuestos y estabilidad

\begin{table}[H]

\caption{\label{tab:anexo-supuestos}Residuo en log (log de la EUI observada menos la predicción en log) dentro del entrenamiento de cada ventana (bosque: fuera de bolsa) y en su año de validación, y número de coeficientes del lasso distintos de 0.}
\centering\small
\begin{tabular}[t]{lr>{\raggedleft\arraybackslash}p{2.4cm}>{\raggedleft\arraybackslash}p{2.4cm}>{\raggedleft\arraybackslash}p{2.4cm}>{\raggedleft\arraybackslash}p{2.4cm}}
\toprule
Modelo & Ventana & Mediana en entrenamiento & Mediana fuera de muestra & Media fuera de muestra & Coef. lasso no nulos\\
\midrule
Lasso & 2019 & 0,006 & −0,099 & −0,097 & 21\\
Lasso & 2020 & 0,007 & −0,044 & −0,081 & 24\\
Lasso & 2021 & 0,003 & −0,009 & −0,046 & 25\\
GAM & 2019 & 0,008 & −0,095 & −0,097 & —\\
GAM & 2020 & 0,009 & −0,058 & −0,098 & —\\
GAM & 2021 & 0,008 & −0,017 & −0,062 & —\\
Bosque & 2019 & 0,009 & −0,058 & −0,067 & —\\
Bosque & 2020 & 0,012 & −0,047 & −0,085 & —\\
Bosque & 2021 & 0,010 & −0,007 & −0,053 & —\\
\bottomrule
\end{tabular}
\end{table}

## Cambio respecto de $a-2$ por tipo de edificio

\begin{table}[H]

\caption{\label{tab:anexo-pandemia}Mediana del cambio log(EUI de $a$ / EUI de $a-2$) por tipo de edificio y año objetivo, en los edificios con ambos valores.}
\centering\small
\begin{tabular}[t]{lrrrrrrr}
\toprule
Tipo & 2017 & 2018 & 2019 & 2020 & 2021 & 2023 & 2024\\
\midrule
Hospital & 0,026 & 0,001 & −0,056 & −0,024 & −0,002 & −0,016 & −0,046\\
Multifamiliar, 10 o más pisos & 0,076 & −0,006 & −0,053 & −0,015 & −0,008 & −0,022 & −0,067\\
Multifamiliar, 1 a 4 pisos & 0,063 & −0,004 & −0,044 & 0,008 & 0,015 & −0,009 & −0,060\\
Multifamiliar, 5 a 9 pisos & 0,060 & 0,000 & −0,037 & 0,000 & 0,000 & 0,007 & −0,040\\
No residencial & 0,049 & −0,010 & −0,054 & −0,138 & −0,096 & 0,010 & −0,061\\
Escuela & 0,100 & −0,062 & −0,059 & −0,079 & 0,186 & −0,104 & −0,173\\
Universidad & 0,084 & 0,027 & −0,037 & −0,062 & −0,017 & 0,042 & −0,051\\
\bottomrule
\end{tabular}
\end{table}

## Error por uso principal en prueba

\begin{table}[H]

\caption{\label{tab:anexo-usos}MAE en prueba (kBtu/pie²) por uso principal del último registro $\leq a-2$. Conservan su nombre los usos con al menos 300 filas en el entrenamiento final, una regla que no mira la prueba; «Otros usos» reúne los demás. Mismas filas para todos los procedimientos en cada grupo.}
\centering\small
\begin{tabular}[t]{lrrrrrrr}
\toprule
Grupo & n & Ref. & Ref. alt. & Lasso & GAM & Bosque & Lasso − ref. alt.\\
\midrule
Vivienda multifamiliar & 3672 & 6,75 & 6,61 & 5,60 & 6,05 & 5,41 & −1,01\\
Oficinas & 963 & 9,26 & 9,15 & 9,26 & 8,78 & 9,29 & +0,11\\
Bodega no refrigerada & 297 & 11,88 & 11,16 & 10,12 & 10,31 & 10,51 & −1,04\\
Escuela (K-12) & 279 & 10,56 & 10,64 & 7,35 & 8,99 & 7,35 & −3,28\\
Hotel & 151 & 14,19 & 13,56 & 17,03 & 16,36 & 18,47 & +3,47\\
Comercio minorista & 143 & 12,98 & 12,49 & 13,57 & 13,23 & 14,08 & +1,08\\
Lugar de culto & 112 & 8,98 & 7,88 & 6,48 & 6,84 & 6,38 & −1,41\\
«Other» de la fuente & 96 & 18,24 & 16,74 & 18,20 & 16,71 & 17,23 & +1,46\\
Otros usos & 1056 & 22,75 & 19,35 & 22,66 & 21,19 & 20,57 & +3,31\\
Sin registro de uso $\leq a-2$ & 232 & 16,94 & 16,94 & 15,29 & 15,32 & 15,72 & −1,66\\
\bottomrule
\end{tabular}
\end{table}

## Mayores errores del lasso en prueba

\begin{table}[H]

\caption{\label{tab:anexo-mayores}Las diez filas de prueba con mayor error absoluto del lasso (EUI en kBtu/pie²).}
\centering\small
\begin{tabular}[t]{rrlrrrr}
\toprule
Edificio & Año & Uso previo & Última EUI & Observada & Lasso & Referencia\\
\midrule
49780 & 2023 & Data Center & 1538,1 & 1639,7 & 927,3 & 1538,1\\
49780 & 2024 & Data Center & 1632,7 & 1656,5 & 979,6 & 1632,7\\
22479 & 2024 & Supermarket/Grocery Store & 282,8 & 740,9 & 236,5 & 282,8\\
24202 & 2024 & Distribution Center & 29,6 & 494,1 & 28,5 & 29,6\\
49967 & 2024 & College/University & 119,5 & 536,1 & 108,0 & 119,5\\
365 & 2023 & Data Center & 909,9 & 989,2 & 641,3 & 909,9\\
753 & 2023 & Data Center & 630,8 & 761,4 & 434,1 & 49,8\\
365 & 2024 & Data Center & 956,7 & 969,8 & 663,2 & 956,7\\
95 & 2024 & Hotel & 87,0 & 367,5 & 75,1 & 49,8\\
753 & 2024 & Data Center & 630,8 & 756,4 & 469,8 & 49,8\\
\bottomrule
\end{tabular}
\end{table}
