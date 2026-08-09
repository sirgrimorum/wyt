# WYT.nvim

Plugin de Neovim para la gestión de proyectos literarios siguiendo la metodología WYT.

## Instalación

**Requisito:**
Este plugin requiere que tengas instalado [`telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim).

> **Importante:** WYT no se auto-inicializa. Debes llamar `require("wyt").setup(...)` en tu
> configuración de Neovim. Sin esta llamada, ningún comando ni mapping estará disponible.

### lazy.nvim (recomendado)

```lua
{
  "tu_usuario/wyt.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("wyt").setup({
      llm_provider = "claude",  -- "openai" | "claude"
      -- Resolver perezoso: lee la key del almacén de credenciales del sistema
      -- en la primera petición. Ver "API key" más abajo.
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
      llm_provider = "claude",
      api_key = require("wyt.secret").os_store(),
    })
  end,
})
```

### Sin plugin manager

En tu `init.lua`, antes del `require`:

```lua
vim.opt.runtimepath:append("/ruta/a/wyt.nvim")
require("wyt").setup()
```

## Configuración

Todas las opciones se pasan a `setup()`. Los valores por defecto son:

```lua
require("wyt").setup({
  llm_provider = "openai",  -- proveedor LLM: "openai" | "claude"
  api_key = "",             -- string | function(): string
})
```

## API key

`api_key` acepta **un string o una función**. Si le pasas una función, WYT no la ejecuta al
arrancar: la llama la primera vez que realmente hace una petición al LLM, y guarda el resultado
en memoria para el resto de la sesión. Así la key nunca se escribe en tu configuración ni queda
disponible para otros procesos.

El módulo `wyt.secret` trae resolvers listos para los almacenes nativos de cada sistema:

```lua
local secret = require("wyt.secret")

api_key = secret.os_store()          -- elige el almacén nativo según el SO (recomendado)
api_key = secret.dpapi()             -- Windows: archivo cifrado con DPAPI
api_key = secret.keychain("wyt")     -- macOS: Keychain
api_key = secret.libsecret("wyt")    -- Linux: libsecret / gnome-keyring
api_key = secret.prompt()            -- pregunta una vez por sesión, no toca el disco
api_key = secret.file("~/.wyt-key")  -- archivo plano (usa permisos 600)
api_key = secret.command({ "pass", "show", "anthropic" })  -- cualquier comando externo
api_key = secret.env("ANTHROPIC_API_KEY")  -- variable de entorno (ver advertencia abajo)
```

### Cómo guardar la key

**Windows (DPAPI).** El texto cifrado queda ligado a tu cuenta de usuario y a esta máquina:
copiarlo a otro equipo no sirve de nada. `Read-Host` evita que la key entre al historial de
PowerShell:

```powershell
$dir = "$env:LOCALAPPDATA\nvim-data\wyt"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Read-Host -AsSecureString "API key" | ConvertFrom-SecureString |
  Set-Content -LiteralPath "$dir\api_key.dpapi"
```

**macOS (Keychain).** Sin `-w <valor>`, `security` pide la key de forma interactiva:

```bash
security add-generic-password -s wyt -a "$USER" -w
```

**Linux (libsecret).** `secret-tool store` lee la key desde stdin:

```bash
secret-tool store --label="WYT" service wyt account default
```

### Por qué no una variable de entorno

Una variable de entorno de usuario la hereda **todo** proceso que lances: servidores LSP,
formateadores, scripts de build, jobs de terminal. Además aparece en volcados de fallo y en la
salida de `env`, que es lo primero que la gente pega en un issue. Un resolver se consulta solo
cuando WYT lo necesita, y solo WYT lo consulta.

Nada de esto protege contra malware que ya corre con tu usuario — ese código también puede leer
tu keychain. Lo que se gana es que la key deja de estar **disponible de forma ambiental** para
procesos que no tienen nada que ver con WYT.

### Cambiar de proveedor en caliente

```
:WYTConfig claude
```

Sin el segundo argumento, WYT pide la key con `inputsecret` (sin eco, y sin pasar por `:history`).
Si la escribes en la línea de comandos, WYT avisa y borra la entrada del historial — pero para
entonces ya pasó por tu pantalla, así que prefiere el prompt.

### Versión de desarrollo

Si se está utilizando la versión local en desarrollo, agrega antes del `require`:

```lua
vim.opt.runtimepath:append '[path to development root folder]/WYT/'
```

Usando una variable de entorno para la ruta:
```lua
require('lazy').setup({
  -- ... tus plugins ...
})

-- [[ WYT (checkout local de desarrollo) ]]
-- Debe ir DESPUÉS de lazy.setup(): lazy reconstruye el 'runtimepath'.
local wyt_path = os.getenv('WYT_PATH')
if wyt_path then
  vim.opt.runtimepath:append(wyt_path)
  require('wyt').setup({
    llm_provider = 'claude',
    api_key = require('wyt.secret').os_store(),
  })
end
```

> **No escribas la API key literal en `init.lua`.** Ese archivo suele estar versionado en git
> (por ejemplo, un fork de kickstart.nvim con remote público), y una key en texto plano ahí
> termina publicada. Usa un resolver de [`wyt.secret`](#api-key).

#### Prueba rápida en una sesión de Neovim en curso

Si no quieres editar `init.lua` todavía y solo quieres probar el plugin en la sesión actual,
ejecuta estos comandos directamente en el prompt `:` de Neovim:

```vim
:lua vim.opt.runtimepath:append("D:/WYT"); require("wyt").setup()
```

Notas:
- Usa **barras hacia adelante** (`D:/WYT`) en Windows; las barras invertidas se interpretan como
  caracteres de escape dentro del string de Lua.
- El cambio es **solo para la sesión actual** — al cerrar Neovim se pierde. Para que sea
  permanente, agrega las mismas dos líneas a tu `init.lua`.

Verifica que el plugin quedó cargado:

```vim
:checkhealth wyt
```

Debes ver la sección `wyt:` con los chequeos de Neovim, telescope, git y `setup()`.

#### Variable de entorno `WYT_PATH`

Solo la **ruta** del checkout va en una variable de entorno; la API key no (ver
[API key](#api-key)).

#### Windows PowerShell

```powershell
[System.Environment]::SetEnvironmentVariable("WYT_PATH", "C:\your\custom\path", "User")
```

Y luego recargar la configuración

```powershell
. $PROFILE
```

O reiniciar la terminal

#### MacOS

Add this line to your `~/.bashrc` or `~/.zshrc`

```bash
export WYT_PATH="/your/custom/path"
```

Y luego recargar la configuración.

Por ejemplo:

```bash
echo 'export WYT_PATH="/ruta/deseada"' >> ~/.zshrc
source ~/.zshrc
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