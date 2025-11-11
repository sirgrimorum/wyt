# Guía de Comandos y Mappings — WYT.nvim

Esta guía describe todos los comandos y atajos de teclado (mappings) disponibles en el plugin **WYT.nvim** para Neovim.

---

## Comandos principales

### Crear entidades

- `:WYTNew p`  
  Crea un nuevo proyecto literario.  
  _Sigue los prompts interactivos para definir idioma, tipo, ruta, nombre, etc._

- `:WYTNew g`  
  Crea un nuevo grupo a partir de ideas seleccionadas en el plan actual.

- `:WYTNew i`  
  Crea una nueva idea y permite agregarla a uno o varios grupos.

---

### Configuración

- `:WYTConfig <proveedor> <api_key>`  
  Configura el proveedor LLM (`openai` o `claude`) y la API Key.

- `:WYTSetLang <en|es>`  
  Cambia el idioma del plugin.

---

### Navegación

- `:WYTNav`  
  Muestra un selector para navegar entre todos los archivos y secciones del proyecto actual.

- `:WYTGoto <plan|config|text|export|parent>`  
  Navega directamente al archivo o sección indicada:
  - `plan`: plan.wyt.md de la sección actual
  - `config`: config.wyt.yml de la sección actual
  - `text`: text.wyt.md de la sección actual
  - `export`: export.wyt.md de la sección actual
  - `parent`: plan.wyt.md de la sección padre

---

### Generación de texto

- `:WYTGenerate [prompt]`  
  Genera texto literario usando el LLM configurado.  
  _Puedes pasar un prompt personalizado._

---

## Mappings (Atajos de teclado)

> **Nota:** Todos los mappings funcionan en modo normal (`n`) y solo en archivos relevantes (por ejemplo, `plan.wyt.md`).

- `<S-Up>`  
  Mueve la idea o grupo actual hacia arriba.

- `<S-Down>`  
  Mueve la idea o grupo actual hacia abajo.

- `<S-Tab>`  
  Navega entre secciones, grupos e ideas según el contexto del cursor en el plan.

---

## Sincronización automática

- Las ideas y grupos se sincronizan automáticamente al editar el `plan.wyt.md` gracias a los autocmds configurados.
- No necesitas ejecutar comandos manuales para mantener la coherencia entre ideas y grupos.

---

## Ejemplo de flujo de trabajo

1. Crea un proyecto con `:WYTNew p`.
2. Agrega ideas con `:WYTNew i`.
3. Agrupa ideas con `:WYTNew g`.
4. Usa `<S-Tab>` para navegar entre grupos y secciones.
5. Usa `:WYTNav` o `:WYTGoto` para moverte entre archivos y secciones.
6. Genera texto con `:WYTGenerate`.

---

## Requisitos

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) debe estar instalado y configurado.

---

¿Tienes dudas o sugerencias?  
Consulta el [README](./README.md) o abre un issue en el repositorio.