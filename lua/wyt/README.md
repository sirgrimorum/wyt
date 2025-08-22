# WYT.nvim

Plugin para la gestión de ideas y grupos literarios en Neovim.

## Instalación

Este plugin requiere [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) como dependencia.

### Usando packer.nvim

```lua
use {
  'sirgrimorum/wyt.nvim',
  requires = { 'nvim-telescope/telescope.nvim' }
}
```

### Usando lazy.nvim

```lua
{
  'sirgrimorum/wyt.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim' }
}
```

## Dependencias

- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

## Uso

Consulta la documentación o los comandos disponibles en el plugin para comenzar a gestionar tus ideas y grupos.

---

**Nota:** Si Telescope no está instalado, el plugin mostrará una advertencia y algunas funciones no