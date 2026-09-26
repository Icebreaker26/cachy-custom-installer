# cachy-custom-installer

Script de instalación personalizada y automatizada de un sistema estilo **CachyOS**
(Arch Linux + repos y kernel de CachyOS + KDE Plasma) pensado para grabarse en **VirtualBox**.

## Qué instala

- Particiones GPT: EFI (512 MB) + raíz **btrfs** con subvolúmenes `@`, `@home`, `@log`, `@cache`, `@snapshots`
- Base Arch con `pacstrap` (kernel `linux` como respaldo)
- Repos, kernel `linux-cachyos` y settings de CachyOS (si falla, continúa con Arch)
- KDE Plasma (sesión X11), SDDM y utilidades de VirtualBox
- GRUB (UEFI, `--removable`)

## Requisitos

- VirtualBox 7.x, ISO de CachyOS o Arch
- VM: Linux / Arch (64-bit), **EFI activado**, 4 GB RAM o más, 40 GB de disco o más, VMSVGA con 128 MB de VRAM, red NAT
- Haz un snapshot de la VM antes de instalar

## Uso

Desde la ISO en vivo, como root:

```bash
curl -O https://raw.githubusercontent.com/<usuario>/cachy-custom-installer/main/install.sh
bash install.sh
```

O servido desde Windows (`python -m http.server` en esta carpeta):

```bash
curl -O http://10.0.2.2:8000/install.sh
bash install.sh
```

## Configuración

Variables al inicio de `install.sh`, sobreescribibles desde el entorno:

| Variable | Por defecto |
|---|---|
| `DISCO` | `/dev/sda` |
| `HOSTNAME_NUEVO` | `cachy-custom` |
| `USUARIO` | `alejandro` |
| `PASS_USUARIO` / `PASS_ROOT` | `cachy123` / `root123` (cámbialas) |
| `ZONA_HORARIA` | `America/Bogota` |
| `LOCALE` / `KEYMAP` | `es_CO.UTF-8` / `la-latin1` |
| `INSTALAR_CACHYOS` | `si` |
| `AUTOLOGIN` | `si` |
| `ASSUME_YES` | `no` (pide confirmación antes de borrar el disco) |

Ejemplo: `DISCO=/dev/nvme0n1 AUTOLOGIN=no bash install.sh`

## Advertencia

El script **borra todo el disco** indicado en `DISCO`. Úsalo solo en una VM o un disco de pruebas.
