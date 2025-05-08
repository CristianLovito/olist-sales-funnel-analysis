# Análisis del funnel de Ventas de Olist


## Idiomas Disponibles:
- [English](README.md)
- [Español](README.español.md)

readme español


## 📖 Descripción del Proyecto

Este proyecto analiza el **e-commerce dataset Olist**, con el objetivo principal de identificar las etapas clave en el **funnel de ventas** y entender en qué puntos los **clientes abandonan su recorrido**. Mediante la **limpieza**, **procesamiento** y **análisis** de los datos, el proyecto busca descubrir insights que pueda ayudar a mejorar la **retención de clientes**, **optimizar los esfuerzos de marketing**, **mejorar el rendimiento general de ventas** y **reducir la tasa de abandono de los clientes**.

### 🔍El análisis se enfocará en lo siguiente:
- Examinar el recorrido del cliente desde la realización del pedido hasta la reseña del producto.

- Identificar los puntos de abandono en cada etapa del funnel de ventas.

- Analizar cómo se relacionan las calificaciones de las reseñas con problemas operativos (por ejemplo, demoras en la entrega).


## 📁 Estructura del Proyecto

```
olist-sales-funnel-analysis/
├── data/
│ ├── charts/
│ └── raw/ # Contiene los datasets originales de Olist
├── sql/ # SQL scripts de los pasos del analysis 
├── .gitignore
├── README.español.md
└── README.md
```
## 🛠 Instalacion

Sin dependencias externas por ahora. Solo cloná el repositorio y empezá a explorar los datos o a ejecutar queries SQL.

---

## 🧹Limpieza de Datos

### 📊 Paso 1: `order_status` y `order_approved_at`
Estados válidos y marcas de tiempo de aprobación -
Este primer paso asegura que **solo analizo órdenes que llegaron a una etapa válida del funnel** y que pasaron controles básicos de calidad.

```sql
WITH cleaned_orders_step1 AS (
SELECT *
FROM olist_orders
WHERE
-- ✅ Conservar solo los estados de orden relevantes
order_status IN ('delivered', 'shipped')

    -- ❌ Eliminar filas sin marca de tiempo de aprobación
    AND order_approved_at IS NOT NULL 

    -- ⏱️ Eliminar outliers extremos con demoras de aprobación mayores a 20 días
    AND EXTRACT(EPOCH FROM (order_approved_at - order_purchase_timestamp)) / 86400 <= 20 
)

SELECT *
FROM cleaned_orders_step1

```

#### 🔍 Paso 1: Limpieza de Order Status y Approval Timestamp

#### 📦 Limpieza de `order_status`

- ❌ Se eliminaron las filas donde `order_status` era:
`canceled`, `unavailable`, `processing`, `invoiced`, `created`, `approved`
(Estas órdenes no fueron enviadas ni entregadas, por lo tanto, no avanzan en el funnel)

- 📉 Filas eliminadas: 1.856

#### 🕒 Limpieza de order_approved_at

- 🧼 Se eliminaron las filas con `order_approved_at` en NULL
(14 filas no tenían timestamp de aprobación a pesar de tener otros timestamp — datos inválidos)

- 📉 Filas eliminadas: 14

#### 🕐 Outliers en el tiempo de aprobación
- 🔍 Se eliminaron filas donde el tiempo de aprobación fue mayor a 20 días
(Los retrasos de aprobación mayores a 20 días probablemente sean anomalías y se consideran datos inválidos)

- 📉 Filas eliminadas: 4

#### ✅ Resumen de datos limpiados

**1**. Se mantuvieron solo los estados de pedido válidos: `delivered`, `shipped`

- ❌ Eliminadas: 1,856 filas

**2**. Verificación obligatoria de la marca de tiempo de aprobación

- ❌ Eliminadas: 14 filas con `order_approved_at` NULL

**3**. Outliers en el retraso de aprobación (retraso de aprobación > 20 días)

- ❌ Eliminadas: 4 filas

### Datos limpios restantes: 97,567 filas

---
### 🔍 Lógica de order_approved_at

Esta consulta se utilizó para validar la consistencia lógica entre `order_purchase_timestamp` y `order_approved_at`.

```sql
SELECT
    CASE 
        WHEN order_approved_at < order_purchase_timestamp THEN '❌ Approval BEFORE Purchase'
        WHEN order_approved_at = order_purchase_timestamp THEN '🟡 Approval at SAME Second'
        WHEN order_approved_at > order_purchase_timestamp THEN '✅ Approval AFTER Purchase'
    END AS approval_timing_category,
    COUNT(*) AS row_count
FROM cleaned_orders_step1
GROUP BY approval_timing_category
ORDER BY row_count DESC
```

#### 🔍 Resumen de la lógica de limpieza

- ❌ Filas con aprobación antes de la compra: 0

- 🟡 Filas con aprobación en el mismo segundo: 1,265 (Se mantienen como plausibles)

- ✅ Filas aprobadas después de la compra: 96,306

- 📉 Filas eliminadas: 0 ✅ Total final restante: 97,567
### Datos limpios restantes ✅ 97,567 filas

*No incluí este filtro en el CTE principal porque los datos ya estaban limpios — ninguna fila tenía aprobación antes de la compra, y las aprobaciones en el mismo segundo (1.265 filas) se consideraron plausibles y se conservaron. Este paso de validación se muestra aquí para demostrar revisiones exhaustivas de calidad de datos.*

---

### 📊 Paso 2: `order_delivered_carrier_date` y tiempo de recogida del transportista

En este paso, limpié los campos `order_delivered_carrier_date` y `days_to_carrier` para asegurarme de que no haya valores inválidos o extremos que distorsionen el análisis.

```sql
WITH cleaned_orders_step2 AS (
    SELECT 
        o.*, 
        ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) AS days_to_approve,
        ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) AS days_to_carrier
    FROM olist_orders o
    WHERE 
        order_status IN ('delivered', 'shipped')  -- ✅ Solo órdenes que pudieron avanzar en el funnel

        -- 🧹 Eliminar filas con timestamps faltantes
        AND order_approved_at IS NOT NULL  
        AND order_delivered_carrier_date IS NOT NULL  

        -- 🧹 Eliminar secuencias lógicamente inválidas
        AND o.order_delivered_carrier_date > o.order_approved_at  
        
        -- ⏱️ Mantener órdenes con demoras de aprobación ≤ 20 días
        AND ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) <= 20 
        
        -- ⏱️ Mantener tiempos de recogida realistas (2 horas a 15 días)
        AND ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) 
            BETWEEN 0.08 AND 15         
)

SELECT * 
FROM cleaned_orders_step2
```

#### 🔍 Limpieza de `order_delivered_carrier_date`

- 🔍 Valores nulos en `order_delivered_carrier_date`:  
❌ Eliminadas: 2 filas

- 🔍 Secuencia inválida: Entregado al transportista antes de la aprobación  
❌ Eliminadas: 1,359 filas



#### ⏱️ Limpieza de days_to_carrier
- ⚡ Recogida del transportista demasiado rápida (< 0.08 días ≈ menos de 2 horas):  
🧹 Filas eliminadas: 935 (probable error del sistema o registro)

- 🐢 Recogida del transportista demasiado lenta (> 15 días):  
🧹 Filas eliminadas: 1,334 (probables fallas operacionales o problemas de datos)


#### ✅ Resumen de datos limpiados

**1.** Valores nulos o secuencias inválidas  
- ❌ Filas eliminadas: 1,361

**2.** Rango aceptable de `days_to_carrier` es **2 horas a 15 días**; todos los valores fuera de este rango se consideran irreales.

- ❌ Filas eliminadas: 935 (Demasiado rápido - probablemente error del sistema o de registro)  
- ❌ Filas eliminadas: 1,334 (Demasiado lento - probablemente fallas operacionales o problemas de datos)

### Datos limpios restantes ✅ 93,937 filas


---

### 📦 Paso 3: `order_delivered_customer_date` y Cálculo del Tiempo de Entrega

Este paso se centra en limpiar la **marca de tiempo de entrega final** a los clientes y calcular **duraciones de entrega realistas**. Aplicamos filtros de calidad para asegurar secuencias de entrega lógicas y eliminar valores atípicos en la **velocidad de entrega**.


```sql
WITH cleaned_orders_step3 AS (
    SELECT 
        o.*, 
        -- ⏱️ Tiempo desde la compra hasta la aprobación
        ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) AS days_to_approve,

        -- ⏱️ Tiempo desde la aprobación hasta la recogida del transportista
        ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) AS days_to_carrier,

        -- ⏱️ Tiempo desde la recogida del transportista hasta la entrega al cliente
        ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400, 2) AS days_to_customer
    FROM olist_orders o
    WHERE 
        order_status IN ('delivered', 'shipped')  -- ✅ Solo pedidos que pudieron continuar en el embudo

        -- 🧹 Eliminar filas con marcas de tiempo faltantes
        AND order_approved_at IS NOT NULL                      
        AND order_delivered_carrier_date IS NOT NULL           
        AND order_delivered_customer_date IS NOT NULL       

        -- 🧹 Eliminar secuencias de tiempo inválidas
        AND o.order_delivered_carrier_date > o.order_approved_at 
        AND o.order_delivered_customer_date >= o.order_delivered_carrier_date 

        -- ⏱️ Mantener pedidos con retrasos en la aprobación ≤ 20 días
        AND ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) <= 20 

        -- ⏱️ Mantener tiempos de recogida realistas (de 2 horas a 15 días)
        AND ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) 
            BETWEEN 0.08 AND 15         

        -- ⏱️ Mantener tiempos de entrega entre 1 y 60 días
        AND ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400, 2) 
            BETWEEN 1 AND 60            
)

SELECT * 
FROM cleaned_orders_step3
```

#### 🔍 Cleaning `order_delivered_customer_date`

- 🧼 Eliminar filas con `order_delivered_customer_date` NULL  
📉 Filas eliminadas: 1,070

- ⛔ Eliminar filas donde la entrega al cliente fue antes de la recogida por parte del transportista  
📉 Filas eliminadas: 23


#### ⏱️ Cleaning `days_to_customer` 

- ⚡ Eliminar entregas demasiado rápidas (**menos de 1 día**) → poco plausible para envíos reales  
📉 Filas eliminadas: 2,499

- 🐢 Eliminar entregas que tardaron más de **60 días** → probablemente casos extremos o problemas de datos  
📉 Filas eliminadas: 217


#### ✅ Resumen de Datos Limpiados  
**1**. Valores nulos o secuencias inválidas

- ❌ Filas eliminadas: 1,070 (`order_delivered_customer_date` es NULL)

- ❌ Filas eliminadas: 23 (`order_delivered_customer_date` antes de `order_delivered_carrier_date`)

**2**. El rango aceptable para `days_to_customer` es de **1 a 60 días**; todos los valores fuera de este rango se consideran irreales.

- ❌ Filas eliminadas: 2,499 (Entrega demasiado rápida: menos de 1 día)

- ❌ Filas eliminadas: 217 (Entrega que tardó más de 60 días - probablemente casos extremos o problemas de datos)

### ✅ Datos restantes limpios: 90,128 filas


---
### 🔍 Curiosidades Adicionales - Análisis de Tiempo de Entrega

```sql
SELECT 
    CASE 
        WHEN order_delivered_customer_date < order_estimated_delivery_date THEN 'Entregado Antes de la Fecha Estimada'
        WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'Entregado Después de la Fecha Estimada'
    END AS delivery_timing,
    COUNT(*) AS row_count
FROM cleaned_orders_step3

GROUP BY delivery_timing
ORDER BY row_count DESC
```

**1**. Pedidos entregados antes de la fecha estimada de entrega
- ✅ 83,221 filas

**2**. Pedidos entregados después de la fecha estimada de entrega
- ❌ 6,907 filas

*Nota:*
También tuve curiosidad por este aspecto, pero no encaja directamente en el paso actual. Quería mostrar estos datos como parte de un análisis futuro. Específicamente, planeo explorar si los pedidos entregados después de lo estimado están vinculados a quejas de los clientes.

---

### ✅ Paso 4: Unión con Reseñas — Análisis de Satisfacción del Cliente

En este paso, integramos la tabla `olist_order_reviews` para incorporar las **calificaciones de satisfacción del cliente** y centrarnos en los pedidos con comentarios positivos.

```sql
WITH cleaned_orders_step4 AS ( 
    SELECT 
        o.*, 
        r.review_score,

        -- ⏱️ Tiempo desde la compra hasta la aprobación
        ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) AS days_to_approve,

        -- ⏱️ Tiempo desde la aprobación hasta la recogida por parte del transportista
        ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) AS days_to_carrier,

        -- ⏱️ Tiempo desde la recogida por parte del transportista hasta la entrega al cliente
        ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400, 2) AS days_to_customer
    FROM olist_orders o

    -- 🔗 Unir con reseñas para obtener la satisfacción del cliente
    JOIN olist_order_reviews r ON o.order_id = r.order_id

    WHERE 
        order_status IN ('delivered', 'shipped')  -- ✅ Solo pedidos que pueden continuar en el embudo

        -- 🧹 Eliminar filas con marcas de tiempo faltantes
        AND order_approved_at IS NOT NULL                       
        AND order_delivered_carrier_date IS NOT NULL           
        AND order_delivered_customer_date IS NOT NULL            

        -- 🧹 Eliminar secuencias de tiempo inválidas
        AND o.order_delivered_carrier_date > o.order_approved_at 
        AND o.order_delivered_customer_date >= o.order_delivered_carrier_date 

        -- ⏱️ Mantener pedidos con retrasos de aprobación ≤ 20 días
        AND ROUND(EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 86400, 2) <= 20 
        
        -- ⏱️ Mantener tiempos de recogida realistas (de 2 horas a 15 días)
        AND ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400, 2) 
            BETWEEN 0.08 AND 15         

        -- ⏱️ Mantener tiempos de entrega entre 1 y 60 días
        AND ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400, 2) 
            BETWEEN 1 AND 60            

        -- 🌟 Solo incluir clientes satisfechos (puntuación de reseña ≥ 4)
        AND r.review_score >= 4         
)

SELECT * 
FROM cleaned_orders_step4
```


### 📦 Uniendo con olist_order_reviews

#### 🔍 Filas sin una revisión de pedido correspondiente:

- ❌ Se eliminaron 789 filas

Estos pedidos no tenían una entrada correspondiente en la tabla de reseñas.



#### ✅ Filas restantes después de la unión: 89,339 filas

### ⭐ Análisis de la Puntuación de Reseñas

#### 📈 Pedidos con una puntuación de reseña de 4 o superior (indicando satisfacción) ✅ Se mantuvieron 70,818 filas

Estos pedidos reflejan una experiencia positiva del cliente y se conservaron para un análisis posterior.


### ✅ Resumen de Datos Limpiados

**1**. Filas sin reseñas coincidentes

- ❌ Se eliminaron 789 filas

**2**. Filtro de puntuación de reseña (solo clientes satisfechos, puntuación de reseña ≥ 4)

- ❌ Se eliminaron 18,521 filas

- ✅ Filas mantenidas: 70,818

*Este proceso nos permite centrarnos en el subconjunto de pedidos con comentarios positivos de los clientes y garantiza que estamos analizando solo aquellas transacciones con datos suficientes para comprender tanto los aspectos operativos como de satisfacción del cliente.*

### Datos limpios restantes ✅ 70,818 filas

---

### 📉 Resumen de Caídas en el Funnel

La siguiente tabla visualiza las caídas progresivas a través de cada etapa importante del **funnel de cumplimiento de e-commerce**. Desde los **99,441 pedidos** iniciales, cada paso de limpieza elimina filas debido a **valores faltantes, plazos irreales o puntuaciones de reseñas insatisfactorias**.

**La caída más significativa** ocurrió al filtrar solo los **pedidos con reseñas positivas (review_score ≥ 4)**, lo que representa una **caída del 20.74%** en las filas en esa etapa.

| **Etapa**             | **Filas Restantes** | **Filas Eliminadas (%)** | **% Acumulado de Filas Conservadas** | **Paso** |
| --------------------- | ------------------- | ------------------------ | ---------------------------------- | -------- |
| Inicial (Sin Limpieza) | 99,441              | -                        | 100%                               | -        |
| Pedido Creado         | 97,585              | 1.86%                    | 98.14%                             | Paso 1   |
| Pedido Aprobado       | 97,567              | 0.02%                    | 98.12%                             | Paso 1   |
| Pedido Enviado        | 93,937              | 3.71%                    | 94.42%                             | Paso 2   |
| Pedido Entregado      | 90,128              | 4.03%                    | 90.66%                             | Paso 3   |
| Unión con Reseñas     | 89,339              | 0.88%                    | 89.97%                             | Paso 4   |
| Reseñas Positivas     | 70,818              | 20.74%                   | 71.32%                             | Paso 4   |


#### *O en un grafico si asi lo ven mejor*

![Sales Funnel Graph](data\charts\sales-funnel-graph.png)
*Nota:* El gráfico fue creado al 100% usando IA después de 20 minutos de iteraciones con Python. La IA ayudó en la generación y optimización de la representación visual del proceso de limpieza de datos de manera eficiente.

---

### 📉 Análisis de la Pérdida en el Funnel:

Explorando el **20.74%** de Pérdida
Como parte del análisis, investigué las razones detrás de la **pérdida del 20.74%** en el funnel, enfocándome específicamente en las **reseñas de 1-3 puntos**. A continuación, se muestra el desglose de las quejas más comunes planteadas por los clientes.

### Hallazgos Clave de las Reseñas de 1-3 Estrellas:
#### Problema	Porcentaje del Total de Quejas	Conteo (300 Reseñas Válidas)

#### 🚚 Problemas de Envío/Entrega (Total) **63.41%** **190**
- Pedidos faltantes al ordenar múltiples productos **9.76%** **30**
- Pedidos retrasados o no recibidos **51.83%** **155**
- Producto bloqueado en aduanas **2.44%** **7**

#### 📦 Problemas con el Producto (Total) **30.49%** **91**
- Versión incorrecta del producto **4.27%** **13**
- Envío de producto incorrecto **4.27%** **13**
- Producto recibido con piezas faltantes **3.66%** **11**
- Producto recibido roto **10.98%** **33**
- Producto engañoso **1.83%** **6**
- Mala calidad de los productos **5.49%** **17**

#### 🧑‍💼 Problemas con el Pedido/Atención al Cliente (Total) **3.05%** **9**
- No se pudo cancelar el pedido **1.83%** **5**
- Mala atención (pésimo servicio al cliente) **1.22%** **4**

#### ❓ Confusión con la Reseña/Calificación (Total) **2.44%** **7**
- ¿Buena reseña, mala calificación? **2.44%** **7**




---


### 🧠 Resumen del Análisis de Reseñas de 1 a 3 Estrellas

#### 🚚 Fuente principal de reseñas negativas (Envío)

El mayor problema, por lejos **(63.4%)**, es el **proceso de envío y entrega**, con más de la mitad **(51.8%)** de las quejas totales relacionadas con productos que llegan **extremadamente tarde** o que no llegan en absoluto. Muchos clientes mencionan que ni siquiera reciben actualizaciones sobre el estado de la entrega, lo que lleva a una completa **frustración, pérdida de confianza** y al abandono del pedido.

#### 📦 Problemas relacionados con el producto
La segunda causa más frecuente **(30.5%)** son los **problemas con el producto en sí**: ya sea que llegue **roto**, sea de **mala calidad** o sea el **producto incorrecto**. Incluso cuando el producto es entregado, existe un **riesgo de 1 en 3** de que decepcione. Muchos usuarios mencionan directamente que **no volverían a pedir** debido a esto.

#### 🧑‍💼 Percepción del servicio al cliente
Solo **el 3%** de las reseñas se quejan directamente del **servicio al cliente**, pero muchas reseñas de otras categorías implican una **falta de apoyo** cuando surgen problemas. **El silencio o la inacción de la empresa cuando los clientes necesitan ayuda** empeora gravemente la experiencia, incluso si no siempre se menciona directamente.

#### ❓ Confusión con la interfaz de reseñas
Finalmente, **el 2.4%** de las reseñas parecen ser **errores de usuario**: personas que dejan buenos comentarios pero asignan malas calificaciones. Esto parece ser una **fallo en la interfaz o en la experiencia del usuario**, pero es menor y no es un problema central.


---


## Recomendaciones Finales
### 🚚 Recomendaciones sobre Envío y Entrega

- **1**. Implementar un **Sistema Básico de Seguimiento de Pedidos**
Los clientes se sienten repetidamente **desinformados** sobre el estado de su pedido. Incluso un panel de seguimiento simple (en la web o app) que muestre si el producto está enviado, en tránsito o retrasado **reduciría drásticamente la frustración**. La visibilidad genera confianza, y en este momento, esa **confianza está rota**.

- **2**. Auditar y **Mejorar el Rendimiento de los Transportistas**
Según el análisis, los retrasos y los productos dañados o faltantes son las dos quejas más comunes. Esto señala una **mala coordinación entre Olist y sus socios de entrega externos**. Olist debería realizar una auditoría del rendimiento de sus operaciones de entrega de última milla y hacer cumplir Acuerdos de Nivel de Servicio (SLA) más estrictos con los transportistas.

- **3**. Tomar Control de los Estándares de Empaque
**Demasiados pedidos** están llegando **roto** o **incompletos**. Olist debería definir y **hacer cumplir directrices de calidad de empaque** para todos los vendedores, o centralizar el empaque en centros de distribución cuando sea posible. **Prevenir** es mejor que las políticas de **reembolso**.

- **4**. **Enfocarse en la Prevención**, No Solo en las Disculpas
No solo ofrezcas políticas de devolución/reembolso; los clientes preferirían **no tener el problema en absoluto**. Olist debe invertir en **mejoras logísticas en la parte anterior** del proceso, en lugar de depender de compensaciones para manejar **fallas en el servicio**.


---

### 🛒 Recomendaciones sobre Calidad del Producto y Supervisión de Vendedores

- **1**. **Reducir listados engañosos mediante auditorías más estrictas de productos**. Olist debería fortalecer el control sobre las descripciones de productos, aplicando un formato claro y estandarizado. Muchas quejas de clientes provienen de **artículos que no cumplen con las expectativas**, lo que probablemente indica que los vendedores están sobrevendiendo o tergiversando sus productos. Un pequeño porcentaje de listados deficientes puede tener un **gran impacto negativo** en la confianza de los clientes.

- **2** **Auditorías de calidad de vendedores** + **penalizaciones por problemas repetidos**. Implementar un sistema automático de puntuación para vendedores basado en tendencias de reseñas, devoluciones y quejas. Los vendedores con problemas frecuentes (por ejemplo, descripciones inexactas, bajas puntuaciones en reseñas) deberían enfrentar **penalizaciones de visibilidad**, menor prioridad en los listados o incluso suspensión si los problemas persisten. Esto **traslada la presión al lado del vendedor** y ayuda a **proteger la marca Olist**.

- **3** **Indicadores de confianza del vendedor visibles para el cliente**. Agregar un sistema simple de insignias de “Vendedor Confiable” o una etiqueta de “Calidad de Producto Verificada” para los listados con **buen rendimiento a largo plazo**. Los clientes necesitan la seguridad de que Olist ha verificado lo que se vende, no solo actuando como intermediario. Esto **aumenta la confiabilidad percibida** de la plataforma y reduce la **ansiedad del comprador**.



### Reflexiones Finales

- Este análisis mostró cómo las ineficiencias operativas, especialmente en la entrega y supervisión de productos, afectan directamente la satisfacción del cliente. Incluso con datos limitados, extraje información significativa y sugerencias accionables. Aún queda espacio para un análisis más profundo de la cadena de suministro y auditorías de la experiencia del usuario, pero esto es un **gran punto de partida**.

### 📌 Aclaración:
*Este análisis se construyó utilizando las marcas de tiempo disponibles del conjunto de datos de Olist para recrear las etapas clave del embudo. Se utilizaron métricas estándar de la industria y expectativas promedio para los plazos de entrega, como las ventanas típicas de aprobación a envío y de envío a entrega, para definir umbrales realistas. Aunque no se disponía de los indicadores exactos de SLA de Olist, la limpieza y la lógica aplicada aquí están alineadas con las mejores prácticas de comercio electrónico para identificar retrasos y problemas operativos.*


---
---

*Este proyecto fue construido a base de esfuerzo, prueba y error, y una incansable motivación por mejorar.  
Por Cristian Lovito — aún no un experto en datos, pero seguro en el camino.*

[GitHub](https://github.com/CristianLovito) · [LinkedIn](https://www.linkedin.com/in/cristian-lovito-06386521a/)

