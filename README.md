# WYT.nvim

Plugin de Neovim para la gestión de proyectos literarios siguiendo la metodología WYT.

## Instalación

**Requisito:**  
Este plugin requiere que tengas instalado [`telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim).

Agrega a tu configuración de Neovim (por ejemplo, usando `lazy.nvim` o `packer.nvim`):

```lua
use({
  'tu_usuario/WYT.nvim',
  requires = { 'nvim-telescope/telescope.nvim' },
  config = function()
    require("wyt").setup()
  end
})
```

## Configuración

No es necesario configurar nada adicional para comenzar. El plugin se inicializa automáticamente.

En tu archivo de configuración de Neovim (`init.lua` o similar), agrega:

```lua
require("wyt").setup()
```

Si deseas personalizar opciones, puedes pasar un objeto de configuración:

```lua
require("wyt").setup({
  -- tus opciones aquí
})
```

Si se está utilizando la versión local en desarrollo. agrega antes del `require`:

```lua
vim.opt.runtimepath:append '[path to development root folder]/WYT/'
```

## ¿Qué archivos y carpetas crea?

- `plan.wyt.md`: Plan principal del proyecto o sección.
- `config.wyt.yml`: Configuración de la sección o proyecto.
- `text.wyt.md`: Texto literario generado.
- `export.wyt.md`: Exportación final del texto.
- Estructura de carpetas para secciones y sub-secciones según la metodología.

## ¿Qué archivos debo modificar?

- No modifiques directamente los archivos internos del plugin.
- Puedes editar los archivos de tu proyecto (`plan.wyt.md`, `text.wyt.md`, etc.) usando Neovim y los comandos/mappings del plugin.

## Uso básico

1. Ejecuta `:WYTNewProject` para crear un nuevo proyecto literario.
2. Navega y administra tu proyecto usando los comandos y mappings proporcionados.
3. Edita y organiza tus ideas, grupos y textos desde los archivos generados.

---

## Guía de comandos y mappings

Consulta la [Guía de Comandos y Mappings](./USER_GUIDE.md) para ver la lista completa de comandos, atajos de teclado y ejemplos de uso.

---

¿Tienes dudas o sugerencias? ¡Abre un issue o contribuye!