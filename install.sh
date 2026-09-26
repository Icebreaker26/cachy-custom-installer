#!/usr/bin/env bash
# =============================================================================
#  Instalación personalizada estilo CachyOS (Arch + repos CachyOS + KDE Plasma)
#  Uso (desde la ISO en vivo de Arch/CachyOS, como root):
#      curl -O http://<host>/install.sh && bash install.sh
#  Etapas: 1 verificar · 2 particionar · 3 formatear · 4 pacstrap · 5 fstab
#          6 chroot (config, CachyOS, KDE, GRUB) · 7 finalizar
# =============================================================================
set -Eeuo pipefail

# ─────────────────────────── CONFIGURACIÓN (editar) ───────────────────────────
DISCO="${DISCO:-/dev/sda}"
HOSTNAME="${HOSTNAME_NUEVO:-cachy-custom}"
USUARIO="${USUARIO:-alejandro}"
PASS_USUARIO="${PASS_USUARIO:-cachy123}"
PASS_ROOT="${PASS_ROOT:-root123}"
ZONA_HORARIA="${ZONA_HORARIA:-America/Bogota}"
LOCALE="${LOCALE:-es_CO.UTF-8}"
KEYMAP="${KEYMAP:-la-latin1}"
INSTALAR_CACHYOS="${INSTALAR_CACHYOS:-si}"   # repos + kernel + settings de CachyOS
AUTOLOGIN="${AUTOLOGIN:-si}"                 # entrar directo al escritorio
ASSUME_YES="${ASSUME_YES:-no}"               # "si" salta la confirmación de borrado
RESUME="${RESUME:-no}"                       # "si" retoma en el chroot con /mnt ya montado

PAQUETES_BASE=(base linux linux-firmware base-devel git sudo nano vim
               networkmanager grub efibootmgr btrfs-progs bash-completion)
PAQUETES_KDE=(plasma-desktop plasma-x11-session xorg-server sddm sddm-kcm
              konsole dolphin kate firefox ark spectacle
              plasma-nm plasma-pa pipewire pipewire-pulse wireplumber
              virtualbox-guest-utils)
PAQUETES_CACHY=(linux-cachyos linux-cachyos-headers cachyos-settings
                cachyos-kde-settings fish paru)
# ──────────────────────────────────────────────────────────────────────────────

C_AZUL=$'\e[1;34m'; C_VERDE=$'\e[1;32m'; C_AMAR=$'\e[1;33m'; C_ROJO=$'\e[1;31m'; C_0=$'\e[0m'
paso()  { echo; echo "${C_AZUL}══> $*${C_0}"; }
ok()    { echo "${C_VERDE} ✔ $*${C_0}"; }
aviso() { echo "${C_AMAR} ! $*${C_0}"; }
die()   { echo "${C_ROJO} ✘ $*${C_0}" >&2; exit 1; }
trap 'die "Falló la línea $LINENO. Revisa install.log"' ERR

# Reintenta un comando hasta 5 veces (redes lentas / mirrors caídos)
reintentar() {
  local n=0
  until "$@"; do
    n=$((n+1)); [[ $n -ge 5 ]] && return 1
    aviso "Falló, reintentando ($n/5)..."; sleep 5
  done
}
# Sin timeout de descarga y con pocas descargas en paralelo
ajustar_pacman() {
  local conf="${1:-/etc/pacman.conf}"
  grep -q '^DisableDownloadTimeout' "$conf" || sed -i '/^\[options\]/a DisableDownloadTimeout' "$conf"
  sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 3/' "$conf"
}

# Sufijo de partición: /dev/sda -> sda1 ; /dev/nvme0n1 -> nvme0n1p1
part() { [[ "$DISCO" =~ [0-9]$ ]] && echo "${DISCO}p$1" || echo "${DISCO}$1"; }

# ═════════════════════════════ PARTE DENTRO DEL CHROOT ═════════════════════════
if [[ "${1:-}" == "--chroot" ]]; then
  # Las variables llegan por /root/vars.env
  source /root/vars.env

  paso "6.1 Hora, idioma y teclado"
  ln -sf "/usr/share/zoneinfo/$ZONA_HORARIA" /etc/localtime
  hwclock --systohc
  sed -i "s/^#\(en_US.UTF-8\)/\1/; s/^#\($LOCALE\)/\1/" /etc/locale.gen
  locale-gen
  echo "LANG=$LOCALE" > /etc/locale.conf
  echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
  echo "$HOSTNAME" > /etc/hostname
  cat > /etc/hosts <<EOF
127.0.0.1  localhost
::1        localhost
127.0.1.1  $HOSTNAME.localdomain $HOSTNAME
EOF
  ok "Localización lista"

  paso "6.2 Usuarios y sudo"
  echo "root:$PASS_ROOT" | chpasswd
  id "$USUARIO" >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash "$USUARIO"
  echo "$USUARIO:$PASS_USUARIO" | chpasswd
  sed -i 's/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers
  ok "Usuario $USUARIO creado"

  paso "6.3 Repositorios y kernel de CachyOS"
  ajustar_pacman
  if [[ "$INSTALAR_CACHYOS" == "si" ]]; then
    (
      set +e
      cd /tmp
      if ! grep -q '^\[cachyos' /etc/pacman.conf; then
        curl -fsSLO https://mirror.cachyos.org/cachyos-repo.tar.xz \
          && tar xf cachyos-repo.tar.xz && cd cachyos-repo \
          && yes | ./cachyos-repo.sh
      fi \
        && ajustar_pacman \
        && reintentar pacman -S --noconfirm --needed "${PAQUETES_CACHY[@]}"
    ) && ok "CachyOS instalado (repos, kernel, settings)" \
      || aviso "CachyOS no se pudo agregar; se continúa con Arch + kernel estándar"
  else
    aviso "INSTALAR_CACHYOS=no, se omite"
  fi

  paso "6.4 Escritorio KDE Plasma (X11) + utilidades VirtualBox"
  ajustar_pacman
  reintentar pacman -S --noconfirm --needed "${PAQUETES_KDE[@]}"
  systemctl enable NetworkManager sddm vboxservice
  mkdir -p /etc/sddm.conf.d
  if [[ "$AUTOLOGIN" == "si" ]]; then
    printf '[Autologin]\nUser=%s\nSession=plasmax11\n' "$USUARIO" > /etc/sddm.conf.d/10-autologin.conf
  else
    printf '[General]\nSession=plasmax11\n' > /etc/sddm.conf.d/10-session.conf
  fi
  if command -v fish >/dev/null; then chsh -s /usr/bin/fish "$USUARIO"; fi
  ok "KDE Plasma configurado"

  paso "6.5 Bootloader GRUB (UEFI)"
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=CachyCustom --removable
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
  grub-mkconfig -o /boot/grub/grub.cfg
  ok "GRUB instalado"

  paso "6.6 Regenerar initramfs"
  mkinitcpio -P
  exit 0
fi

# ═════════════════════════════ PARTE EN LA ISO EN VIVO ═════════════════════════
exec > >(tee -a install.log) 2>&1

if [[ "$RESUME" == "si" ]]; then
  mountpoint -q /mnt || die "RESUME=si requiere el sistema montado en /mnt"
  aviso "Retomando: se omiten las etapas 1 a 5"
else
paso "1/7 Verificaciones"
[[ $EUID -eq 0 ]]             || die "Ejecuta como root"
[[ -d /sys/firmware/efi ]]    || die "No arrancó en UEFI: activa EFI en la VM"
[[ -b "$DISCO" ]]             || die "No existe el disco $DISCO (lsblk para ver)"
ping -c1 -W3 archlinux.org >/dev/null 2>&1 || die "Sin internet"
timedatectl set-ntp true
ok "UEFI, disco $DISCO e internet correctos"
lsblk "$DISCO"

if [[ "$ASSUME_YES" != "si" ]]; then
  read -rp "Esto BORRARÁ TODO en $DISCO. ¿Continuar? [s/N] " r
  [[ "$r" =~ ^[sS]$ ]] || die "Cancelado por el usuario"
fi

paso "2/7 Particionando $DISCO (EFI 512M + raíz btrfs)"
umount -R /mnt 2>/dev/null || true
wipefs -af "$DISCO"
sgdisk -Z "$DISCO"
sgdisk -n1:0:+512M -t1:ef00 -c1:EFI  "$DISCO"
sgdisk -n2:0:0     -t2:8300 -c2:ROOT "$DISCO"
partprobe "$DISCO"; sleep 1
ok "Tabla GPT creada"

paso "3/7 Formateando y montando (subvolúmenes btrfs)"
mkfs.fat -F32 -n EFI "$(part 1)"
mkfs.btrfs -f -L CACHY "$(part 2)"
mount "$(part 2)" /mnt
for sv in @ @home @log @cache @snapshots; do btrfs subvolume create "/mnt/$sv"; done
umount /mnt
OPT="noatime,compress=zstd:3,ssd,discard=async"
mount -o "$OPT,subvol=@" "$(part 2)" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache,.snapshots}
mount -o "$OPT,subvol=@home"      "$(part 2)" /mnt/home
mount -o "$OPT,subvol=@log"       "$(part 2)" /mnt/var/log
mount -o "$OPT,subvol=@cache"     "$(part 2)" /mnt/var/cache
mount -o "$OPT,subvol=@snapshots" "$(part 2)" /mnt/.snapshots
mount "$(part 1)" /mnt/boot
ok "Sistema montado en /mnt"; lsblk "$DISCO"

paso "4/7 Instalando sistema base (pacstrap)"
ajustar_pacman
reintentar pacstrap -K /mnt "${PAQUETES_BASE[@]}"
ok "Base instalada"

paso "5/7 Generando fstab"
genfstab -U /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab
fi

paso "6/7 Configuración dentro del sistema nuevo (chroot)"
cat > /mnt/root/vars.env <<EOF
HOSTNAME='$HOSTNAME'
USUARIO='$USUARIO'
PASS_USUARIO='$PASS_USUARIO'
PASS_ROOT='$PASS_ROOT'
ZONA_HORARIA='$ZONA_HORARIA'
LOCALE='$LOCALE'
KEYMAP='$KEYMAP'
INSTALAR_CACHYOS='$INSTALAR_CACHYOS'
AUTOLOGIN='$AUTOLOGIN'
DISCO='$DISCO'
PAQUETES_KDE=(${PAQUETES_KDE[*]})
PAQUETES_CACHY=(${PAQUETES_CACHY[*]})
EOF
cp "$0" /mnt/root/install.sh
arch-chroot /mnt bash /root/install.sh --chroot
rm -f /mnt/root/vars.env /mnt/root/install.sh

paso "7/7 Finalizando"
umount -R /mnt
ok "Instalación completa. Saca la ISO de la VM y reinicia."
read -rp "¿Reiniciar ahora? [s/N] " r
[[ "$r" =~ ^[sS]$ ]] && reboot || echo "Escribe 'reboot' cuando quieras."
