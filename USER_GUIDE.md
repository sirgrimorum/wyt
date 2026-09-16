# Guía de usuario de WYT.nvim

Esta guía describe los comandos, los atajos de teclado y las reglas que WYT
aplica a un proyecto. Para verlo todo en uso, de principio a fin, consulta el
[caso de uso completo](./docs/use_case_e2e.md).

- [Estructura de un proyecto](#estructura-de-un-proyecto)
- [Comandos](#comandos)
- [Cómo usar :WYTGenerate](#cómo-usar-wytgenerate)
- [Mappings](#mappings)
- [Comportamiento automático](#comportamiento-automático)
- [Tipos de texto](#tipos-de-texto)
- [Mapa de títulos](#mapa-de-títulos)
- [Arquetipos de sección](#arquetipos-de-sección)
- [Ejemplo de flujo de trabajo](#ejemplo-de-flujo-de-trabajo)

---

## Estructura de un proyecto

Un proyecto WYT son archivos de texto plano en carpetas, versionados con git.
No hay nada escondido en una base de datos.

| Archivo | Contiene |
|---------|----------|
| `config.wyt.yml` | idioma, tipo literario, arquetipo y si este nivel anida sub-secciones |
| `plan.wyt.md` | la descripción, las ideas sueltas y los grupos en que se reúnen |
| `text.wyt.md` | la prosa, un párrafo por idea, escrita o generada |
| `export.wyt.md` | el documento ensamblado, reconstruido por `:WYTExport` |

Un **grupo** es un conjunto de ideas que van juntas. `<S-Tab>` sobre la cabecera
de un grupo lo convierte en una **sección** propia, con su plan y sus grupos, o
lo escribe directamente en `text.wyt.md` como un marcador por idea. Cuál de las
dos ocurre depende de la profundidad del tipo, más abajo.

---

## Comandos

### Crear entidades

- `:WYTNew p`
  Crea un nuevo proyecto literario.
  _Sigue los prompts interactivos: idioma, tipo, ruta, nombre, carpeta raíz,
  tipo de contenido, sub-secciones (solo si el tipo admite más de un nivel) y
  dónde abrirlo. Si la carpeta raíz ya tiene archivos, pide confirmación: cada
  guardado hace commit de todo lo que hay en ella. Si la carpeta está dentro de
  otro proyecto también pregunta: WYT toma como raíz el proyecto más externo, así
  que el nuevo se leería como una sección suya._

- `:WYTNew i`
  Agrega una idea al plan actual, libre o respondiendo las preguntas
  orientadoras del tipo, una a una.

- `:WYTNew g`
  Crea un grupo con las ideas seleccionadas del plan actual.

### Configuración

- `:WYTConfig <proveedor>`
  Configura el proveedor LLM (`openai` o `claude`) y pide la API key sin eco,
  fuera del historial.

- `:WYTSetLang <en|es>`
  Cambia el idioma del plugin y lo guarda en el `config.wyt.yml` del proyecto.
  _No reescribe lo que ya está escrito. WYT solo reconoce las marcas en el idioma
  actual, así que en un proyecto con grupos los `## Grupo:` dejan de ser grupos
  para la navegación, la búsqueda y el export. Elige el idioma al crear el
  proyecto; si cambias, vuelve al anterior y todo reaparece._

### Navegación

- `:WYTNav`
  Selector para navegar entre todos los archivos y secciones del proyecto.

- `:WYTGoto <plan|config|text|export|parent>`
  Navega directamente al archivo indicado:
  - `plan`: `plan.wyt.md` de la sección actual
  - `config`: `config.wyt.yml` de la sección actual
  - `text`: `text.wyt.md` de la sección actual
  - `export`: `export.wyt.md` de la raíz del proyecto
  - `parent`: `plan.wyt.md` de la sección padre

- `:WYTSearch`
  Busca dentro de las secciones de referencia.

### Escritura y generación

- `:WYTGenerate [instrucción]`
  Genera en el punto donde está el cursor y lo inserta ahí.
  _La instrucción es opcional: sin ella, la posición decide la tarea. Ver
  [Cómo usar :WYTGenerate](#cómo-usar-wytgenerate)._

- `:WYTExpand`, `:WYTExpand next`, `:WYTExpand prev`
  Expande el marcador de párrafo en el cursor, o busca el siguiente o el
  anterior y lo expande.

- `:WYTExport`
  Ensambla todas las secciones en el `export.wyt.md` de la raíz.

- `:checkhealth wyt`
  Verifica dependencias, proveedor LLM y de dónde sale la API key.

`:WYTSearch` lee cada sección cuyo arquetipo la hace material de referencia,
tanto su `plan.wyt.md` como su `text.wyt.md`. Una sección de Personajes casi
nunca llega a escribirse en prosa, así que la mayor parte de lo que buscas está
en el plan: los grupos son las entradas y las ideas bajo cada uno son lo que
sabes de ella. Cada resultado viene etiquetado con la cabecera bajo la que
está, de modo que un rasgo te dice de quién es:

```
cast/plan.wyt.md:7 (Ana): - se queda callada cuando tiene miedo
```

---

## Cómo usar :WYTGenerate

El cursor no es solo el sitio donde se pega el resultado: es parte de la
pregunta. Antes de llamar al modelo, WYT lee dónde estás y qué tienes alrededor,
y arma el prompt con eso. Nunca hace falta explicar el contexto a mano.

Lo que se envía siempre:

- **El proyecto**: el tipo literario, con su nombre en tu idioma y no con el id,
  más la descripción del `plan.wyt.md`.
- **Dónde está el cursor**: la cabecera más cercana por encima, ya sea la
  sección o el grupo, sin la marca `Grupo:` ni las etiquetas de estado.
- **Qué clase de párrafo quiere el tipo**: a un ensayo se le pide uno
  argumentativo, a una novela uno narrativo, a un resumen uno de notas. La
  columna "Párrafo que pide al modelo" de [Tipos de texto](#tipos-de-texto) los
  lista. En `plan.wyt.md` no aplica: ahí se piden ideas, no prosa.

Lo que se envía según el archivo:

| Estás en | Se envía además | Sin instrucción, pide | Se inserta como |
|----------|-----------------|-----------------------|-----------------|
| `text.wyt.md`, entre dos párrafos | el párrafo anterior y el siguiente | un párrafo que lleve de uno a otro | prosa |
| `text.wyt.md`, después del último párrafo | el párrafo anterior | el párrafo que sigue | prosa |
| `plan.wyt.md`, dentro de un grupo | las ideas que ya están en ese grupo | ideas nuevas que no repitan las existentes | ideas `- ` |
| `plan.wyt.md`, bajo `## Ideas` | las ideas sueltas que ya hay | ideas nuevas para la sección | ideas `- ` |
| cualquier otro archivo | el párrafo anterior y el siguiente | un puente entre ellos, o el párrafo que sigue | prosa |

Tres formas de usarlo, entonces:

**Un conector entre párrafos.** Deja el cursor en la línea en blanco que separa
dos párrafos y ejecuta `:WYTGenerate` sin argumentos. El modelo recibe los dos
párrafos y escribe el puente.

```vim
:WYTGenerate
:WYTGenerate que sea una sola frase, seca
```

**Lluvia de ideas en un grupo o sección.** Deja el cursor en la cabecera del
grupo, o en cualquiera de sus ideas, dentro de `plan.wyt.md`. El modelo recibe
las ideas que ya están ahí y propone hasta cinco nuevas, que se insertan como
ideas de la lista, no como prosa.

```vim
:WYTGenerate
:WYTGenerate ideas que contradigan las anteriores
```

**Cualquier otra cosa, con instrucción.** La instrucción sustituye a la tarea por
defecto, pero el contexto se sigue enviando igual, así que no tienes que repetir
de qué va el proyecto ni en qué grupo estás.

```vim
:WYTGenerate describe el lugar con tres detalles concretos
:WYTGenerate reescribe el párrafo anterior en tercera persona
```

En un plan, el resultado se convierte siempre en ideas de una línea con su `- `,
aunque el modelo responda con una lista numerada o con prosa. Un párrafo suelto
dentro de un `plan.wyt.md` no sería una idea, y la sincronización automática lo
arrastraría a todos los grupos.

---

## Mappings

> **Nota:** todos los mappings son de buffer y funcionan en modo normal (`n`),
> solo en archivos WYT. No pisan tus atajos en el resto de buffers.

| Tecla | Archivo | Acción |
|-------|---------|--------|
| `<S-Tab>` | `plan.wyt.md` | Navegación según el contexto: implementar el grupo como sección, entrar en la sección, o volver al plan padre |
| `<S-Up>` | `plan.wyt.md` | Mueve la idea o el grupo actual hacia arriba |
| `<S-Down>` | `plan.wyt.md` | Mueve la idea o el grupo actual hacia abajo |
| `<leader>we` | `text.wyt.md` | Expande el marcador en el cursor |
| `]w` | `text.wyt.md` | Salta al siguiente marcador y lo expande |
| `[w` | `text.wyt.md` | Salta al marcador anterior y lo expande |

Toda navegación de WYT, por mapping o por comando, hace dos cosas antes de
moverse: guarda el archivo actual si tiene cambios sin escribir, lo que además
dispara el commit automático, y busca una ventana que ya muestre el destino.
Así no se pierde trabajo en un salto, y ir y volver entre un plan y su sección
reutiliza las dos pestañas en lugar de acumular copias.

---

## Comportamiento automático

Esto ocurre solo, sin que tengas que ejecutar nada:

| Disparador | Archivo | Efecto |
|------------|---------|--------|
| `BufEnter` | `plan.wyt.md` | Lee el idioma del config, lo aplica y activa los mappings del buffer |
| `BufEnter` | `text.wyt.md` | Igual, con los mappings de texto |
| `TextChanged`, `InsertLeave` | `*plan.wyt.md` | Sincroniza con 300 ms de espera: las ideas de los grupos se reflejan en la sección `## Ideas` |
| `BufWritePost` | `*plan.wyt.md` | Commit automático: `"Save: plan.wyt.md"` |
| `BufWritePost` | `*text.wyt.md` | Commit automático: `"Save: text.wyt.md"` |

Cada guardado hace commit, así que la historia del proyecto es la historia de la
escritura. Nunca necesitas tocar git a mano.

El texto que devuelve el modelo se limpia antes de entrar en un archivo: se le
quitan los títulos, los bloques de código y las viñetas. Un `#` inventado por el
modelo se leería como estructura y acabaría siendo una sección del export.

---

## Tipos de texto

| Nombre en el menú | Tipo | Preguntas orientadoras | Párrafo que pide al modelo | Lógica de párrafos | Profundidad máxima |
|---|---|---|---|---|---|
| Novela | `novel` | Arco, personaje, escena | Un párrafo narrativo | 1 idea → 1 párrafo | 3 niveles |
| Novela larga | `long_novel` | Hilo conductor, parte, trama secundaria, cronología | Un párrafo narrativo | 1 idea → 1 párrafo | 4 niveles |
| Novela corta | `short_novel` | Escena, deseo, consecuencia | Un párrafo narrativo | 1 idea → 1 párrafo | 2 niveles |
| Cuento | `short_story` | Foco narrativo, tono | Un párrafo literario | 1 idea → 1 párrafo | 1 nivel |
| Ensayo | `essay` | Argumento, evidencia, perspectiva | Un párrafo argumentativo | 1 idea → 1 párrafo | 2 niveles |
| Resumen | `summary` | Punto clave, síntesis | Un párrafo de notas conciso | Varias ideas → 1 párrafo | 1 nivel |

**Nombre en el menú** es lo que ves al crear el proyecto, junto a una línea que
dice qué le hace ese tipo al texto final. El **tipo** de la segunda columna es
el id que se guarda en `config.wyt.yml`; nunca aparece en pantalla.

**Preguntas orientadoras** es el segundo modo de `:WYTNew i`. Llegan de una en
una y cada respuesta se convierte en una idea. El tipo decide cuáles son, y el
arquetipo de una sección puede reemplazarlas por las suyas.

**Párrafo que pide al modelo** es lo que cambia en el prompt cuando expandes un
marcador o usas `:WYTGenerate`: a un ensayo se le pide un párrafo argumentativo
y a una novela uno narrativo. Al modelo también se le da el nombre del tipo en
tu idioma, nunca el id: *Novela larga*, no `long_novel`.

**Profundidad máxima** cuenta niveles de plan, siendo el plan raíz el nivel 1.
Una sección creada con `<S-Tab>` recibe `sections: true` mientras esté por
debajo del límite, así que sus propios grupos se vuelven secciones a su vez; en
el límite recibe `sections: false` y sus grupos van directos a `text.wyt.md`.
Un `essay` anida entonces un nivel de secciones bajo la raíz, una `novel` dos,
una `long_novel` tres, y `short_story` y `summary` ninguno: sus grupos van
directos al texto. El asistente solo pregunta "¿Tendrá sub-secciones?" a los
tipos que permiten más de un nivel.

**Lógica de párrafos** decide qué escribe `<S-Tab>` en `text.wyt.md`. Todos los
tipos menos `summary` escriben un marcador por idea. `summary` condensa: el
grupo entero se vuelve un solo marcador con todas sus ideas separadas por `;`,
y al expandirlo se obtiene un párrafo que las funde.

### Hacer que una rama baje un nivel más

La profundidad del tipo es solo el valor por defecto **al crear** una sección.
Lo que de verdad gobierna a una sección es su propio `sections:`, y ese
interruptor lo puedes editar a mano. Si una rama concreta necesita un nivel más
del que su tipo reparte, abre el `config.wyt.yml` de esa sección y pon
`sections: true`:

```yaml
type: essay
section_kind: prose
content_type: definition
sections: true    # esta sección anida, aunque el ensayo ya estuviera en su límite
```

A partir de ahí, `<S-Tab>` sobre un grupo de esa sección crea una sub-sección en
lugar de mandar el grupo a `text.wyt.md`. El cambio es **local a esa rama**: sus
secciones hermanas siguen con `sections: false` y siguen escribiendo texto, y
las sub-secciones nuevas se crean con el valor que les toca por el tipo, así que
el árbol no se desborda solo. No hay ninguna clave global de profundidad, ni
hace falta: para un ensayo que quieres entero en tres niveles, el sitio correcto
es el tipo.

Dos detalles que conviene tener claros:

- El interruptor solo decide lo que pasa **de ahí en adelante**. Ponerlo a
  `false` en una sección que ya tiene sub-secciones no las borra ni las saca del
  export; solo hace que el próximo `<S-Tab>` escriba texto en vez de crear otra.
- El [mapa de títulos](#mapa-de-títulos) solo declara niveles hasta la
  profundidad propia del tipo. Un nivel de más no lleva título: sus bloques
  simplemente salen uno tras otro, separados por una línea en blanco, dentro del
  título del nivel que sí está declarado. El export no se rompe, pero tampoco
  titula. Si quieres títulos ahí, el tipo es el sitio donde declararlos.

---

## Mapa de títulos

Los mismos nombres, colocados igual, se componen distinto según la forma: un
ensayo titula sus secciones, una novela titula sus capítulos pero nunca sus
escenas. Cada tipo declara en qué se convierte un nombre de un nivel dado
cuando se genera el export.

| Tipo | nivel 2 | nivel 3 | nivel 4 | grupos dentro de `text.wyt.md` |
|------|---------|---------|---------|--------------------------------|
| `novel` | capítulo `##` | escena: `* * *` | - | nada |
| `long_novel` | parte `##` | capítulo `###` | escena: `* * *` | nada |
| `short_novel` | escena: `* * *` | - | - | nada |
| `short_story` | - | - | - | escena: `* * *` |
| `essay` | sección `##` | - | - | nada |
| `summary` | - | - | - | `##` por grupo |

La raíz es siempre el título del documento, así que ningún tipo declara el nivel
1. "Nada" quiere decir que los bloques simplemente siguen, separados por una
línea en blanco: los párrafos de un ensayo no quieren un título cada uno, y los
de una novela tampoco.

Las líneas `## Grupo: ...` dentro de `text.wyt.md` son marcas del propio WYT,
puestas ahí para poder volver a encontrar un grupo cuando se reimplementa. En el
export se resuelven con este mapa, no se copian al documento. Los marcadores sin
expandir se descartan igual: una instrucción que te escribiste a ti mismo no es
parte del texto.

El mismo proyecto, ensamblado como tres tipos distintos:

```
ENSAYO                               NOVELA                                 RESUMEN
# El silencio de las ciudades        # Anochecer                            # Notas de la reunión

## El espacio urbano                 ## Capítulo uno                        ## Lo que se decidió

La ciudad zumba antes del alba.      La verja llevaba años sin aceite.      El lanzamiento pasa a marzo.

Las plazas contenían el aliento.     * * *                                  ## Lo que queda abierto

## La economía de la atención        Llegó con tres inviernos de retraso.   Nadie se ha hecho cargo.

La calle suena ahora en la mesa.     ## Capítulo dos
```

---

## Arquetipos de sección

Un arquetipo dice para qué es una sección. Se pregunta una sola vez, cuando
`<S-Tab>` la crea, y a partir de ahí decide tres cosas: las preguntas
orientadoras de esa sección, si llega al export, y si `:WYTSearch` la ve.

| Arquetipo | Para | Se exporta |
|-----------|------|------------|
| Prosa | el texto mismo; guiada por el tipo del proyecto | sí |
| Personajes | un grupo por personaje: deseo, necesidad, herida, voz | no, pero es buscable |
| Escenario | los lugares y las reglas del mundo | no, pero es buscable |
| Cronología | cuándo ocurre cada cosa, en orden de la historia | no, pero es buscable |
| Puntos de giro | lo que lo cambia todo, y lo que cuesta | no, pero es buscable |
| Temas | de qué trata la obra por debajo | no, pero es buscable |
| Conceptos clave | los términos en que se apoya el argumento | no, pero es buscable |
| Fuentes | la evidencia que citas | no, pero es buscable |
| Contraargumentos | las objeciones que responde el ensayo | sí |

Cuáles se ofrecen depende del tipo:

| Tipo | Arquetipos ofrecidos |
|------|----------------------|
| `novel`, `long_novel`, `short_novel`, `short_story` | Prosa, Personajes, Escenario, Cronología, Puntos de giro, Temas |
| `essay` | Prosa, Conceptos clave, Fuentes, Contraargumentos, Temas |
| `summary` | Prosa, Conceptos clave, Fuentes |

Una sección de referencia se trabaja como cualquier otra: sus grupos son las
entradas (un personaje, un concepto, una fecha) y las ideas bajo cada uno son lo
que sabes. Si le das a un personaje una sección propia, hereda el arquetipo sin
volver a preguntar, porque una sección de una sección de Personajes sigue siendo
sobre personajes.

Contraargumentos es el único arquetipo con forma de referencia que sí se
exporta: las objeciones se escriben dentro del ensayo, no solo se recopilan.

---

## Ejemplo de flujo de trabajo

```
:WYTNew p          crear el proyecto y su repositorio git
:WYTNew i (×N)     reunir ideas, libres o con las preguntas del tipo
:WYTNew g (×N)     agrupar las ideas que van juntas
<S-Up>/<S-Down>    ordenar grupos e ideas
<S-Tab>            convertir un grupo en sección, o en texto
<S-Tab>            entrar en la sección y refinarla con :WYTNew i/g
]w  [w             expandir los marcadores en párrafos
:WYTGenerate       insertar texto generado donde haga falta
:WYTSearch         consultar personajes, cronología o conceptos al escribir
:WYTNav            recorrer el árbol del proyecto
:WYTGoto parent    volver al plan padre
:WYTExport         ensamblar el export final
```

---

## Requisitos

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) instalado y
  configurado.

¿Tienes dudas o sugerencias?
Consulta el [README](./README.md) o abre un issue en el repositorio.
