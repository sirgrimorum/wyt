# WYT.nvim

Plugin de Neovim para la gestión de proyectos literarios siguiendo la metodología WYT.

## Requisitos

- Neovim >= 0.10
- [`telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim)
- `git` y `curl` en el PATH

WYT no se auto-inicializa. Sin una llamada a `require("wyt").setup(...)` no se registra ningún
comando ni mapping.

## Instalación

### lazy.nvim

```lua
{
  "tu_usuario/wyt.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("wyt").setup({
      llm_provider = "claude",  -- "openai" | "claude"
      api_key = require("wyt.secret").os_store(),
    })
  end,
}
```

### packer.nvim

```lua
use({
  "tu_usuario/wyt.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("wyt").setup({
      llm_provider = "claude",  -- "openai" | "claude"
      api_key = require("wyt.secret").os_store(),
    })
  end,
})
```

### Sin plugin manager

```lua
vim.opt.runtimepath:append("/ruta/a/wyt.nvim")
require("wyt").setup({
  llm_provider = "claude",  -- "openai" | "claude"
  api_key = require("wyt.secret").os_store(),
})
```

Si además usas lazy.nvim, este bloque va **después** de `require('lazy').setup(...)`.
Ver [Desarrollo local](#desarrollo-local).

## Configuración

```lua
require("wyt").setup({
  llm_provider = "openai",  -- "openai" | "claude"
  api_key = "",             -- string | function(): string
})
```

## API key

`api_key` acepta un string o una función. Si le pasas una función, WYT la llama en la primera
petición al LLM, no al arrancar, y guarda el resultado en memoria para el resto de la sesión.
La key nunca queda escrita en tu configuración.

El módulo `wyt.secret` trae resolvers listos:

| Resolver | De dónde lee la key |
| --- | --- |
| `secret.os_store()` | Almacén nativo del sistema. Recomendado. |
| `secret.dpapi()` | Windows, archivo cifrado con DPAPI |
| `secret.keychain("wyt")` | macOS Keychain |
| `secret.libsecret("wyt")` | Linux, libsecret o gnome-keyring |
| `secret.prompt()` | Pregunta una vez por sesión. No toca el disco. |
| `secret.file("~/.wyt-key")` | Archivo plano. Usa permisos 600. |
| `secret.command({ "pass", "show", "anthropic" })` | Salida de cualquier comando |
| `secret.env("ANTHROPIC_API_KEY")` | Variable de entorno. Ver [abajo](#por-qué-no-una-variable-de-entorno). |

### Guardar la key

**Windows (DPAPI).** El cifrado queda ligado a tu usuario y a esta máquina, así que el archivo
no sirve en otro equipo. `Read-Host` mantiene la key fuera del historial de PowerShell.

```powershell
$dir = "$env:LOCALAPPDATA\nvim-data\wyt"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Read-Host -AsSecureString "API key" | ConvertFrom-SecureString |
  Set-Content -LiteralPath "$dir\api_key.dpapi"
```

**macOS (Keychain).** Sin `-w <valor>`, `security` pide la key de forma interactiva.

```bash
security add-generic-password -s wyt -a "$USER" -w
```

**Linux (libsecret).** `secret-tool store` lee la key desde stdin.

```bash
secret-tool store --label="WYT" service wyt account default
```

### Cambiar de proveedor

```
:WYTConfig claude
```

Sin segundo argumento, WYT pide la key con `inputsecret`, sin eco y sin pasar por `:history`.
Si la escribes en la línea de comandos, WYT avisa y borra la entrada del historial, pero para
entonces ya estuvo en pantalla. Usa el prompt.

### Por qué no una variable de entorno

Una variable de entorno de usuario la hereda todo proceso que lances: servidores LSP,
formateadores, scripts de build, jobs de terminal. También aparece en volcados de fallo y en la
salida de `env`. Un resolver se consulta solo cuando WYT lo necesita.

Esto no protege contra malware que ya corre con tu usuario, porque ese código también puede leer
tu keychain. Lo que evita es que la key esté disponible de forma ambiental para procesos que no
tienen nada que ver con WYT.

## Desarrollo local

Para usar un checkout local en vez de la versión instalada, agrega la ruta al `runtimepath` y
llama a `setup()`:

```lua
require('lazy').setup({
  -- ... tus plugins ...
})

-- Va DESPUÉS de lazy.setup(): lazy reconstruye el 'runtimepath' y descarta
-- cualquier ruta agregada antes de esa llamada.
local wyt_path = os.getenv('WYT_PATH')
if wyt_path then
  vim.opt.runtimepath:append(wyt_path)
  require('wyt').setup({
    llm_provider = 'claude',  -- "openai" | "claude"
    api_key = require('wyt.secret').os_store(),
  })
end
```

WYT se carga entero con `require`, y `require` busca dentro de `lua/` de cada entrada del
`runtimepath`: esa línea de `append` es lo que hace que `require('wyt')` encuentre el checkout.
Si el bloque corre antes de `lazy.setup()`, lazy reconstruye el `runtimepath` y la ruta se pierde:
lo ya cargado sigue respondiendo en esa sesión, pero el siguiente `require` de un submódulo, y
cualquier reinicio, falla. Para comprobarlo:

```vim
:lua print(vim.o.runtimepath:find('WYT') ~= nil)
```

No escribas la API key literal en `init.lua`. Ese archivo suele estar versionado en git, y una
key en texto plano ahí termina publicada. Usa un resolver de [`wyt.secret`](#api-key).

### Prueba rápida sin editar init.lua

```vim
:lua vim.opt.runtimepath:append("C:/ruta/a/WYT"); require("wyt").setup()
```

Usa barras hacia adelante en Windows: las invertidas son escapes dentro de un string de Lua.
El cambio dura solo la sesión actual.

### Definir WYT_PATH

Solo la ruta del checkout va en una variable de entorno. La API key no.

Windows PowerShell:

```powershell
[System.Environment]::SetEnvironmentVariable("WYT_PATH", "C:\tu\ruta", "User")
```

macOS y Linux, en `~/.bashrc` o `~/.zshrc`:

```bash
export WYT_PATH="/tu/ruta"
```

En ambos casos, reinicia la terminal o recarga el perfil.

## Verificar la instalación

```vim
:checkhealth wyt
```

Reporta versión de Neovim, telescope, git, el proveedor LLM y de dónde sale la API key. Nunca
imprime la key.

## Tests

```sh
nvim --headless -l tests/runner.lua              # todo
nvim --headless -l tests/runner.lua types llm    # solo esos specs
```

No hay nada que instalar y ninguna llamada al LLM: los tests reemplazan
`generate_text` por un doble, así que corren sin API key. Sale con código 1 si
algo falla. Ver [tests/README.md](./tests/README.md) para escribir uno.

## ¿Qué archivos y carpetas crea?

- `plan.wyt.md`: Plan principal del proyecto o sección.
- `config.wyt.yml`: Configuración de la sección o proyecto.
- `text.wyt.md`: Texto literario generado.
- `export.wyt.md`: Exportación final del texto.
- Estructura de carpetas para secciones y sub-secciones según la metodología.

## ¿Qué archivos debo modificar?

No modifiques los archivos internos del plugin. Edita los archivos de tu proyecto
(`plan.wyt.md`, `text.wyt.md`, etc.) con Neovim y los comandos del plugin.

## Uso básico

1. Ejecuta `:WYTNew p` para crear un nuevo proyecto literario.
2. Navega y administra tu proyecto con los comandos y mappings.
3. Edita y organiza tus ideas, grupos y textos desde los archivos generados.

## Documentación

- [Guía de usuario](./USER_GUIDE.md): la lista completa de comandos y atajos, el
  comportamiento automático, los tipos de texto con su profundidad y su lógica de
  párrafos, el mapa de títulos del export y los arquetipos de sección
  (personajes, cronología, puntos de giro, conceptos clave, fuentes).
- [Caso de uso completo](./docs/use_case_e2e.md): el recorrido de la metodología
  de principio a fin, desde un directorio vacío hasta el export final.
- [Tests](./tests/README.md): cómo correr la suite y cómo escribir un spec.
- [AGENTS.md](./AGENTS.md): para contribuir, con o sin un asistente de código.
  Las decisiones ya tomadas y las trampas que han costado tiempo.

---

¿Tienes dudas o sugerencias? ¡Abre un issue o contribuye!
