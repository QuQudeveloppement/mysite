#!/usr/bin/env bash
# ============================================================================
#  QUENTIN OS pour Linux Mint Cinnamon
#  Remplace l'apparence complète du bureau : fond, thème GTK/Cinnamon (verre,
#  bordures cyan/violet), icônes, barre des tâches, menu, widgets, terminal,
#  écran de connexion. Réversible.
#
#  Usage :  bash quentin-os-mint.sh [install|uninstall] [--no-plymouth] [--no-media]
#  (écran de démarrage + menu GRUB QUENTIN OS inclus par défaut)
#  À lancer en utilisateur normal (sudo sera demandé), dans une session Cinnamon.
# ============================================================================
set -euo pipefail

ACTION="install"; PLY=1; MEDIA=1
for a in "$@"; do case "$a" in install|uninstall) ACTION="$a";; --plymouth) PLY=1;; --no-plymouth) PLY=0;; --no-media) MEDIA=0;; esac; done

DATA="$HOME/.local/share/quentin-os"
BACKUP="$HOME/.quentin-os-backup"
THEME="Quentin-Glass"
SYS_BG="/usr/share/backgrounds/quentin-os"

log() { printf '\033[1;36m[QUENTIN OS]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERREUR]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Ne lancez pas ce script avec sudo : lancez-le en utilisateur normal."
case "${XDG_CURRENT_DESKTOP:-}" in *Cinnamon*) ;; *) die "Session Cinnamon requise (actuel : ${XDG_CURRENT_DESKTOP:-inconnu}).";; esac
command -v gsettings >/dev/null || die "gsettings introuvable."
command -v dconf >/dev/null || die "dconf introuvable."

# ----------------------------------------------------------------------------
uninstall() {
  log "Restauration de l'apparence d'origine…"
  if [ -f "$BACKUP/cinnamon.dconf" ]; then
    dconf reset -f /org/cinnamon/ || true
    dconf load /org/cinnamon/ < "$BACKUP/cinnamon.dconf"
    [ -f "$BACKUP/nemo.dconf" ] && { dconf reset -f /org/nemo/ || true; dconf load /org/nemo/ < "$BACKUP/nemo.dconf"; }
    [ -f "$BACKUP/terminal.dconf" ] && { dconf reset -f /org/gnome/terminal/ || true; dconf load /org/gnome/terminal/ < "$BACKUP/terminal.dconf"; }
    [ -f "$BACKUP/interface.dconf" ] && { dconf reset -f /org/gnome/desktop/interface/ || true; dconf load /org/gnome/desktop/interface/ < "$BACKUP/interface.dconf"; }
  else
    log "Pas de sauvegarde trouvée : réinitialisation aux valeurs par défaut de Cinnamon."
    dconf reset -f /org/cinnamon/ || true
  fi
  pkill conky 2>/dev/null || true
  rm -rf "$HOME"/.local/share/cinnamon/desklets/quentin-*
  rm -f "$HOME/.config/autostart/quentin-conky.desktop" "$HOME/.config/conky/quentin.conf"
  sudo rm -rf "/usr/share/themes/$THEME" "$SYS_BG"
  if [ -f "$BACKUP/slick-greeter.conf.orig" ]; then sudo cp "$BACKUP/slick-greeter.conf.orig" /etc/lightdm/slick-greeter.conf
  else sudo rm -f /etc/lightdm/slick-greeter.conf; fi
  if [ -d /usr/share/plymouth/themes/quentin ]; then
    sudo update-alternatives --remove default.plymouth /usr/share/plymouth/themes/quentin/quentin.plymouth 2>/dev/null || true
    sudo plymouth-set-default-theme -R "$(cat "$BACKUP/plymouth.orig" 2>/dev/null || echo bgrt)" 2>/dev/null || sudo update-initramfs -u || true
    sudo rm -rf /usr/share/plymouth/themes/quentin
  fi
  if [ -f /etc/default/grub.d/99-quentin.cfg ]; then
    sudo rm -f /etc/default/grub.d/99-quentin.cfg
    sudo update-grub || true
  fi
  rm -rf "$DATA"
  nohup cinnamon --replace >/dev/null 2>&1 &
  disown || true
  log "Terminé. Apparence d'origine restaurée."
  exit 0
}
[ "$ACTION" = "uninstall" ] && uninstall

# ----------------------------------------------------------------------------
log "1/8 Sauvegarde de votre configuration actuelle dans $BACKUP"
mkdir -p "$BACKUP" "$DATA"
if [ ! -f "$BACKUP/cinnamon.dconf" ]; then   # ne jamais écraser la 1re sauvegarde
  dconf dump /org/cinnamon/ > "$BACKUP/cinnamon.dconf"
  dconf dump /org/nemo/ > "$BACKUP/nemo.dconf"
  dconf dump /org/gnome/terminal/ > "$BACKUP/terminal.dconf"
  dconf dump /org/gnome/desktop/interface/ > "$BACKUP/interface.dconf"
  [ -f /etc/lightdm/slick-greeter.conf ] && cp /etc/lightdm/slick-greeter.conf "$BACKUP/slick-greeter.conf.orig"
  command -v plymouth-set-default-theme >/dev/null && plymouth-set-default-theme > "$BACKUP/plymouth.orig" 2>/dev/null || true
fi

log "2/8 Installation des dépendances (sudo requis)"
if ! sudo apt-get update -qq; then
  log "apt-get update a échoué (souvent : horloge de la machine en retard ou en avance, fréquent en machine virtuelle)."
  log "Synchronisation de l'heure puis nouvel essai dans 15 s..."
  sudo timedatectl set-ntp true 2>/dev/null || true
  sleep 15
  sudo apt-get update -qq || die "apt-get update échoue encore. Vérifiez la date/l'heure (commande : date) et la connexion Internet, puis relancez."
fi
sudo apt-get install -y librsvg2-bin papirus-icon-theme fonts-inter python3 dconf-cli

if [ "$MEDIA" -eq 1 ]; then
  log "2b/8 Applications multimédia (lecteurs, codecs, audio, vidéo, image) - gros téléchargement"
  WANT="mint-meta-codecs ffmpeg vlc celluloid rhythmbox audacity pavucontrol easyeffects obs-studio kdenlive handbrake gimp inkscape shotwell mediainfo-gui yt-dlp"
  AVAIL=()
  for pk in $WANT; do
    c=$(apt-cache policy "$pk" 2>/dev/null | awk '/Candidate:/{print $2}')
    if [ -n "${c:-}" ] && [ "$c" != "(none)" ]; then AVAIL+=("$pk"); else log "   (paquet absent des dépôts, ignoré : $pk)"; fi
  done
  sudo apt-get install -y "${AVAIL[@]}" || log "   (une partie des applications n'a pas pu être installée)"
fi

# ----------------------------------------------------------------------------
log "3/8 Création des ressources graphiques (fond, logo)"
python3 - "$DATA" <<'PYEOF'
import random, sys
out = sys.argv[1]
random.seed(7)
stars = "".join(
    f'<circle cx="{random.randint(0,1920)}" cy="{random.randint(0,700)}" r="{random.choice([0.6,0.9,1.3,1.8])}" fill="#fff" opacity="{random.uniform(.3,.95):.2f}"/>'
    for _ in range(260))
wall = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1080" width="1920" height="1080">
<defs>
 <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#050816"/><stop offset=".55" stop-color="#14104a"/><stop offset="1" stop-color="#2a0f5e"/></linearGradient>
 <radialGradient id="planet" cx=".35" cy=".35" r=".8"><stop offset="0" stop-color="#e0f2fe"/><stop offset=".35" stop-color="#38bdf8"/><stop offset="1" stop-color="#1e1b6b"/></radialGradient>
 <radialGradient id="halo" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#38bdf8" stop-opacity=".55"/><stop offset="1" stop-color="#38bdf8" stop-opacity="0"/></radialGradient>
 <radialGradient id="moon" cx=".4" cy=".4" r=".7"><stop offset="0" stop-color="#fbcfe8"/><stop offset=".5" stop-color="#c084fc"/><stop offset="1" stop-color="#3b0764"/></radialGradient>
 <linearGradient id="mtn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4c1d95"/><stop offset=".4" stop-color="#1e1550"/><stop offset="1" stop-color="#05030f"/></linearGradient>
 <linearGradient id="rim" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#22d3ee"/><stop offset="1" stop-color="#e879f9"/></linearGradient>
 <filter id="blur"><feGaussianBlur stdDeviation="14"/></filter>
</defs>
<rect width="1920" height="1080" fill="url(#sky)"/>
{stars}
<circle cx="960" cy="470" r="420" fill="url(#halo)"/>
<circle cx="960" cy="470" r="250" fill="url(#planet)"/>
<path d="M740 430 A250 250 0 0 1 1180 360" fill="none" stroke="#bae6fd" stroke-width="4" opacity=".8"/>
<circle cx="1230" cy="330" r="62" fill="url(#moon)"/>
<ellipse cx="1000" cy="560" rx="620" ry="90" fill="#7c3aed" opacity=".35" filter="url(#blur)"/>
<path d="M0 1080 L0 800 L180 700 L300 760 L520 560 L640 650 L820 470 L960 600 L1110 520 L1300 720 L1480 600 L1700 760 L1920 690 L1920 1080 Z" fill="url(#mtn)"/>
<path d="M520 560 L600 640 L560 650 L520 620 L490 650 L470 620 Z M820 470 L900 570 L860 580 L820 550 L790 580 L760 560 Z M1480 600 L1540 670 L1500 675 L1470 650 L1440 675 Z" fill="#e0e7ff" opacity=".85"/>
<path d="M0 800 L180 700 L300 760 L520 560 L640 650 L820 470 L960 600 L1110 520 L1300 720 L1480 600 L1700 760 L1920 690" fill="none" stroke="url(#rim)" stroke-width="3" opacity=".9"/>
<g transform="translate(760,900) scale(.55)" opacity=".95">
 <circle cx="150" cy="150" r="82" fill="none" stroke="#22d3ee" stroke-width="14"/>
 <path d="M168 168 L214 214" stroke="#a855f7" stroke-width="16" stroke-linecap="round"/>
 <text x="270" y="140" font-family="Inter, DejaVu Sans, sans-serif" font-size="78" font-weight="700" letter-spacing="6" fill="#fff">QUENTIN</text>
 <text x="274" y="212" font-family="Inter, DejaVu Sans, sans-serif" font-size="64" font-weight="300" letter-spacing="22" fill="#22d3ee">OS</text>
</g>
</svg>'''
icon = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
 <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#22d3ee"/><stop offset="1" stop-color="#a855f7"/></linearGradient></defs>
 <circle cx="128" cy="128" r="84" fill="none" stroke="url(#g)" stroke-width="20"/>
 <path d="M150 150 L200 200" stroke="url(#g)" stroke-width="22" stroke-linecap="round"/>
</svg>'''
full = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 300" width="800" height="300">
 <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#22d3ee"/><stop offset="1" stop-color="#a855f7"/></linearGradient></defs>
 <circle cx="150" cy="150" r="82" fill="none" stroke="url(#g)" stroke-width="14"/>
 <path d="M168 168 L214 214" stroke="url(#g)" stroke-width="16" stroke-linecap="round"/>
 <text x="270" y="140" font-family="Inter, DejaVu Sans, sans-serif" font-size="78" font-weight="700" letter-spacing="6" fill="#fff">QUENTIN</text>
 <text x="274" y="212" font-family="Inter, DejaVu Sans, sans-serif" font-size="64" font-weight="300" letter-spacing="22" fill="#22d3ee">OS</text>
</svg>'''
barbg = '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="8"><rect width="400" height="8" rx="4" fill="#ffffff" fill-opacity="0.15"/></svg>'
barfill = '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="8"><defs><linearGradient id="g"><stop offset="0" stop-color="#22d3ee"/><stop offset="1" stop-color="#a855f7"/></linearGradient></defs><rect width="400" height="8" rx="4" fill="url(#g)"/></svg>'
GRAD = '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#22d3ee"/><stop offset="1" stop-color="#a855f7"/></linearGradient></defs>'
GRAD2 = '<defs><linearGradient id="g" x1="1" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#a855f7"/><stop offset="1" stop-color="#22d3ee"/></linearGradient></defs>'
extra = {
 "ring-outer": '<svg xmlns="http://www.w3.org/2000/svg" width="360" height="360" viewBox="0 0 360 360">' + GRAD + '<circle cx="180" cy="180" r="170" fill="none" stroke="url(#g)" stroke-width="4" stroke-linecap="round" stroke-dasharray="260 120 90 200 140 258"/></svg>',
 "ring-inner": '<svg xmlns="http://www.w3.org/2000/svg" width="280" height="280" viewBox="0 0 280 280">' + GRAD2 + '<circle cx="140" cy="140" r="130" fill="none" stroke="url(#g)" stroke-width="3" stroke-linecap="round" stroke-dasharray="120 60 200 80 150 207"/></svg>',
 "halo": '<svg xmlns="http://www.w3.org/2000/svg" width="640" height="640" viewBox="0 0 640 640"><defs><radialGradient id="h"><stop offset="0" stop-color="#38bdf8" stop-opacity="0.45"/><stop offset="0.5" stop-color="#7c3aed" stop-opacity="0.18"/><stop offset="1" stop-color="#7c3aed" stop-opacity="0"/></radialGradient></defs><circle cx="320" cy="320" r="320" fill="url(#h)"/></svg>',
 "star": '<svg xmlns="http://www.w3.org/2000/svg" width="6" height="6"><circle cx="3" cy="3" r="2.4" fill="#ffffff"/></svg>',
 "dot": '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><circle cx="7" cy="7" r="5" fill="#22d3ee"/></svg>',
 "logo-text": '<svg xmlns="http://www.w3.org/2000/svg" width="560" height="110" viewBox="0 0 560 110"><text x="280" y="75" text-anchor="middle" font-family="Inter, DejaVu Sans, sans-serif" font-size="60" font-weight="700" letter-spacing="10" fill="#ffffff">QUENTIN <tspan fill="#22d3ee" font-weight="300">OS</tspan></text></svg>',
}
for name, svg in extra.items():
    open(f"{out}/{name}.svg", "w").write(svg)
open(f"{out}/logo-full.svg", "w").write(full)
open(f"{out}/bar-bg.svg", "w").write(barbg)
open(f"{out}/bar-fill.svg", "w").write(barfill)
open(f"{out}/wallpaper.svg", "w").write(wall)
open(f"{out}/logo-icon.svg", "w").write(icon)
PYEOF
for spec in hd:1280:720 fhd:1920:1080 2k:2560:1440 4k:3840:2160; do
  IFS=: read -r n w h <<<"$spec"
  rsvg-convert -w "$w" -h "$h" "$DATA/wallpaper.svg" -o "$DATA/wallpaper-$n.png"
done
rsvg-convert -w 256 -h 256 "$DATA/logo-icon.svg" -o "$DATA/logo-icon.png"
rsvg-convert -w 560 "$DATA/logo-full.svg" -o "$DATA/logo-full.png"
rsvg-convert "$DATA/bar-bg.svg" -o "$DATA/bar-bg.png"
rsvg-convert "$DATA/bar-fill.svg" -o "$DATA/bar-fill.png"
for n in ring-outer ring-inner halo star dot logo-text; do rsvg-convert "$DATA/$n.svg" -o "$DATA/$n.png"; done
rsvg-convert -w 190 -h 190 "$DATA/logo-icon.svg" -o "$DATA/ply-icon.png"
sudo mkdir -p "$SYS_BG"
sudo cp "$DATA"/wallpaper-*.png "$DATA/logo-icon.png" "$DATA/logo-icon.svg" "$DATA/logo-full.png" "$SYS_BG/"
sudo chmod -R a+rX "$SYS_BG"

# Choix de la résolution du fond selon l'écran principal
W=$(xdpyinfo 2>/dev/null | awk '/dimensions:/{split($2,a,"x"); print a[1]}' || true); W=${W:-1920}
if   [ "$W" -ge 3200 ]; then WP=4k; elif [ "$W" -ge 2200 ]; then WP=2k; elif [ "$W" -ge 1700 ]; then WP=fhd; else WP=hd; fi
WALL="$SYS_BG/wallpaper-$WP.png"
# (fond 4k conservé pour l'écran de connexion)

# ----------------------------------------------------------------------------
log "4/8 Création du thème $THEME (GTK + Cinnamon + fenêtres)"
BASE=""
for t in Mint-Y-Dark-Aqua Mint-Y-Dark Mint-Y-Dark-Purple; do [ -d "/usr/share/themes/$t" ] && { BASE="$t"; break; }; done
[ -n "$BASE" ] || die "Thème de base Mint-Y-Dark introuvable."
TMP="$(mktemp -d)"
cp -a "/usr/share/themes/$BASE" "$TMP/$THEME"
sed -i "s/^Name=.*/Name=$THEME/; s/^Comment=.*/Comment=QUENTIN OS - verre, cyan et violet/" "$TMP/$THEME/index.theme" 2>/dev/null || true
sed -i "s/$BASE/$THEME/g" "$TMP/$THEME/index.theme" 2>/dev/null || true

GTKCSS='
/* ===== QUENTIN OS : glassmorphism ===== */
@define-color qos_cyan #22d3ee;
@define-color qos_violet #a855f7;
window, .background { background-color: rgba(11,16,48,0.86); color: #e0f2fe; }
headerbar, .titlebar { background: linear-gradient(90deg, rgba(34,211,238,.20), rgba(168,85,247,.20)); border-bottom: 1px solid rgba(34,211,238,.45); }
decoration { border-radius: 14px; border: 1px solid rgba(168,85,247,.55); box-shadow: 0 8px 32px rgba(124,58,237,.45), 0 0 0 1px rgba(34,211,238,.25); }
button { border-radius: 10px; border: 1px solid rgba(34,211,238,.40); background-image: none; background-color: rgba(255,255,255,.06); transition: all 150ms ease; }
button:hover { background-color: rgba(34,211,238,.22); box-shadow: 0 0 10px rgba(34,211,238,.55); }
button.suggested-action, button:checked { background-image: linear-gradient(90deg,#22d3ee,#a855f7); color: #050816; }
entry, spinbutton, textview text { border-radius: 10px; border: 1px solid rgba(34,211,238,.35); background-color: rgba(5,8,22,.65); color: #e0f2fe; }
entry:focus { border-color: #22d3ee; box-shadow: 0 0 8px rgba(34,211,238,.6); }
*:selected, row:selected, selection { background-color: rgba(168,85,247,.60); color: #fff; }
scrollbar slider { border-radius: 8px; background-color: rgba(34,211,238,.50); }
menu, .popup, tooltip { border-radius: 12px; border: 1px solid rgba(168,85,247,.55); background-color: rgba(10,12,40,.94); }
.nemo-window .sidebar, .nemo-window .view { background-color: rgba(8,12,40,.78); }
.nemo-window .nemo-places-sidebar row:selected { background-image: linear-gradient(90deg,rgba(34,211,238,.4),rgba(168,85,247,.4)); }
'
for f in gtk-3.0/gtk.css gtk-3.0/gtk-dark.css; do
  [ -f "$TMP/$THEME/$f" ] && printf '%s\n' "$GTKCSS" >> "$TMP/$THEME/$f"
done

CINCSS='
/* ===== QUENTIN OS : shell Cinnamon ===== */
#panel { background-color: rgba(10,14,50,0.72); border-top: 1px solid rgba(34,211,238,0.55); box-shadow: 0 -4px 24px rgba(124,58,237,0.35); font-weight: bold; }
.panel-top, .panel-bottom { background-color: rgba(10,14,50,0.72); }
.window-list-item-box { border-radius: 10px; margin: 4px 2px; }
.window-list-item-box:hover { background-color: rgba(34,211,238,0.25); box-shadow: 0 0 10px rgba(34,211,238,0.5); }
.window-list-item-box:focus, .grouped-window-list-item-box:focus { background-color: rgba(168,85,247,0.40); border-bottom: 2px solid #22d3ee; }
.menu { background-color: rgba(10,12,40,0.90); border: 1px solid rgba(168,85,247,0.65); border-radius: 18px; box-shadow: 0 10px 40px rgba(124,58,237,0.55); }
.menu-applications-inner-box, .menu-favorites-box, .menu-categories-box { background-color: transparent; }
.menu-application-button-selected, .menu-category-button-selected { background-color: rgba(34,211,238,0.28); border-radius: 12px; box-shadow: 0 0 8px rgba(34,211,238,0.5); }
.menu-search-entry { background-color: rgba(5,8,22,0.7); border: 1px solid rgba(34,211,238,0.5); border-radius: 14px; color: #e0f2fe; }
.popup-menu, .calendar { background-color: rgba(10,12,40,0.92); border: 1px solid rgba(168,85,247,0.55); border-radius: 14px; }
.notification { background-color: rgba(10,12,40,0.92); border: 1px solid rgba(34,211,238,0.6); border-radius: 14px; }
.expo-workspaces-name-entry, .workspace-thumbnail-indicator { border-color: #22d3ee; }
'
CINCSS2='
/* ===== QUENTIN OS : barre des tâches refaite ===== */
#panel { background-color: rgba(8,10,38,0.78); border-top: 2px solid rgba(34,211,238,0.70); box-shadow: 0 -6px 30px rgba(124,58,237,0.45); }
.applet-box { padding: 0 6px; border-radius: 14px; margin: 6px 2px; transition-duration: 150; }
.applet-box:hover { background-color: rgba(34,211,238,0.20); box-shadow: 0 0 12px rgba(34,211,238,0.5); }
.applet-label { color: #e0f2fe; font-weight: bold; padding: 0 6px; }
.panel-launchers .launcher { border-radius: 14px; }
.grouped-window-list-item-box { border-radius: 16px; margin: 6px 4px; padding: 0 10px; background-color: rgba(255,255,255,0.05); border-bottom: 3px solid transparent; transition-duration: 150; }
.grouped-window-list-item-box:hover { background-color: rgba(34,211,238,0.22); box-shadow: 0 0 16px rgba(34,211,238,0.6); }
.grouped-window-list-item-box:focus, .grouped-window-list-item-box:active { background-color: rgba(168,85,247,0.34); border-bottom: 3px solid #22d3ee; box-shadow: 0 0 16px rgba(168,85,247,0.7); }
.grouped-window-list-item-box:running { border-bottom: 3px solid rgba(168,85,247,0.9); }
.grouped-window-list-thumbnail-menu, .grouped-window-list-thumbnail-alert { background-color: rgba(10,12,40,0.94); border: 1px solid rgba(168,85,247,0.6); border-radius: 16px; padding: 8px; }
.window-list-preview, .grouped-window-list-badge { border-radius: 10px; }
.calendar-today { background-color: rgba(34,211,238,0.35); border-radius: 12px; }
/* ===== QUENTIN OS : écran de verrouillage (meilleur effort, selon version) ===== */
.unlock-dialog, .unlockdialog, #unlock-dialog { background-color: rgba(10,12,40,0.78); border: 1px solid rgba(168,85,247,0.65); border-radius: 22px; box-shadow: 0 10px 40px rgba(124,58,237,0.55); padding: 20px; }
.csstage, .csstage .lockscreen { color: #e0f2fe; }
.clock-box, .clock { color: #e0f2fe; text-shadow: 0 0 18px rgba(34,211,238,0.8); }
'
[ -f "$TMP/$THEME/cinnamon/cinnamon.css" ] && printf '%s\n%s\n' "$CINCSS" "$CINCSS2" >> "$TMP/$THEME/cinnamon/cinnamon.css"
for f in gtk-3.0/gtk.css gtk-3.0/gtk-dark.css; do
  [ -f "$TMP/$THEME/$f" ] && printf '%s\n' "$CINCSS2" | sed -n '/verrouillage/,$p' >> "$TMP/$THEME/$f"
done
sudo rm -rf "/usr/share/themes/$THEME"
sudo cp -a "$TMP/$THEME" /usr/share/themes/
sudo chmod -R a+rX "/usr/share/themes/$THEME"
rm -rf "$TMP"

# ----------------------------------------------------------------------------
log "5/8 Application de l'interface (thème, icônes, panneau, menu, effets)"
gs() { gsettings set "$@" 2>/dev/null || log "  (ignoré : $1 $2)"; }
gs org.cinnamon.desktop.interface gtk-theme "$THEME"
gs org.cinnamon.desktop.interface icon-theme "Papirus-Dark"
gs org.cinnamon.desktop.interface font-name "Inter 10"
gs org.cinnamon.desktop.wm.preferences theme "$THEME"
gs org.cinnamon.theme name "$THEME"
gs org.cinnamon.desktop.background picture-uri "file://$WALL"
gs org.cinnamon.desktop.background picture-options "zoom"
gs org.cinnamon.desktop.wm.preferences button-layout ":minimize,maximize,close"
gs org.cinnamon desktop-effects true
gs org.cinnamon desktop-effects-workspace true
gs org.cinnamon.desktop.interface cursor-size 24
gs org.cinnamon.desktop.interface gtk-theme "$THEME"

# Barre des tâches unique en bas, plus haute, style Windows 11/QUENTIN OS
gs org.cinnamon panels-enabled "['1:0:bottom']"
gs org.cinnamon panels-height "['1:56']"
gs org.cinnamon panels-autohide "['1:false']"
gs org.cinnamon panel-zone-icon-sizes '[{"panelId": 1, "left": 26, "center": 34, "right": 22}]'
gs org.cinnamon panel-zone-symbolic-icon-sizes '[{"panelId": 1, "left": 22, "center": 24, "right": 20}]'
gs org.cinnamon enabled-applets "['panel1:left:0:expo@cinnamon.org:0', 'panel1:left:1:show-desktop@cinnamon.org:1', 'panel1:center:0:menu@cinnamon.org:2', 'panel1:center:1:grouped-window-list@cinnamon.org:3', 'panel1:right:0:systray@cinnamon.org:4', 'panel1:right:1:notifications@cinnamon.org:5', 'panel1:right:2:keyboard@cinnamon.org:6', 'panel1:right:3:network@cinnamon.org:7', 'panel1:right:4:sound@cinnamon.org:8', 'panel1:right:5:power@cinnamon.org:9', 'panel1:right:6:calendar@cinnamon.org:10']"
# Écran de verrouillage : grande horloge, police Inter, message QUENTIN OS
gs org.cinnamon.desktop.screensaver use-custom-format true
gs org.cinnamon.desktop.screensaver time-format '%H:%M'
gs org.cinnamon.desktop.screensaver date-format '%A %d %B %Y'
gs org.cinnamon.desktop.screensaver font-time 'Inter Bold 110'
gs org.cinnamon.desktop.screensaver font-date 'Inter 26'
gs org.cinnamon.desktop.screensaver font-message 'Inter 16'
gs org.cinnamon.desktop.screensaver default-message 'QUENTIN OS'
gs org.cinnamon.desktop.screensaver show-clock true
gs org.cinnamon.desktop.screensaver show-album-art false
gs org.cinnamon favorite-apps "['firefox.desktop', 'nemo.desktop', 'org.gnome.Terminal.desktop', 'mintinstall.desktop', 'cinnamon-settings.desktop', 'org.gnome.Calculator.desktop', 'vlc.desktop', 'org.gnome.Rhythmbox3.desktop', 'xed.desktop']"
gs org.nemo.desktop show-desktop-icons true

# Terminal : SEULEMENT les couleurs (pas de transparence, police et réglages inchangés)
if command -v gnome-terminal >/dev/null; then
  PID=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'" || true)
  if [ -n "$PID" ]; then
    P="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PID/"
    gsettings set "$P" use-theme-colors false || true
    gsettings set "$P" background-color '#0B1030' || true
    gsettings set "$P" foreground-color '#E0F2FE' || true
    gsettings set "$P" use-transparent-background false || true
    gsettings set "$P" palette "['#0B1030','#F43F5E','#34D399','#FBBF24','#38BDF8','#A855F7','#22D3EE','#E0F2FE','#475569','#FB7185','#6EE7B7','#FCD34D','#7DD3FC','#C084FC','#67E8F9','#FFFFFF']" || true
    gsettings set "$P" cursor-background-color '#22D3EE' || true
    gsettings set "$P" cursor-colors-set true || true
  fi
fi

# ----------------------------------------------------------------------------
log "6/8 Widgets du bureau (desklets : déplaçables à la souris, supprimables par clic droit)"
pkill conky 2>/dev/null || true
rm -f "$HOME/.config/autostart/quentin-conky.desktop" "$HOME/.config/conky/quentin.conf"
DK="$HOME/.local/share/cinnamon/desklets"
mkdir -p "$DK/quentin-clock@quentin-os" "$DK/quentin-system@quentin-os"

cat > "$DK/quentin-clock@quentin-os/metadata.json" <<'JSONEOF'
{"uuid": "quentin-clock@quentin-os", "name": "QUENTIN OS - Horloge", "description": "Heure et date, style QUENTIN OS", "max-instances": "1", "version": "1.0"}
JSONEOF
cat > "$DK/quentin-clock@quentin-os/desklet.js" <<'JSEOF'
const Desklet = imports.ui.desklet;
const St = imports.gi.St;
const Mainloop = imports.mainloop;

const JOURS = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"];
const MOIS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"];
function pad(n) { return n < 10 ? "0" + n : "" + n; }

function QuentinClock(metadata, desklet_id) { this._init(metadata, desklet_id); }
QuentinClock.prototype = {
    __proto__: Desklet.Desklet.prototype,
    _init: function (metadata, desklet_id) {
        Desklet.Desklet.prototype._init.call(this, metadata, desklet_id);
        this.box = new St.BoxLayout({ vertical: true, style: "background-color: rgba(11,16,48,0.80); border: 1px solid rgba(168,85,247,0.65); border-radius: 20px; padding: 16px 26px; width: 250px;" });
        this.time = new St.Label({ style: "font-size: 56px; font-weight: bold; color: #22d3ee;" });
        this.date = new St.Label({ style: "font-size: 15px; color: #e0f2fe;" });
        this.box.add_child(this.time);
        this.box.add_child(this.date);
        this.setContent(this.box);
        this._tick();
    },
    _tick: function () {
        let d = new Date();
        this.time.set_text(pad(d.getHours()) + ":" + pad(d.getMinutes()));
        this.date.set_text(JOURS[d.getDay()] + " " + d.getDate() + " " + MOIS[d.getMonth()] + " " + d.getFullYear());
        this._timeout = Mainloop.timeout_add_seconds(5, () => { this._tick(); return false; });
    },
    on_desklet_removed: function () {
        if (this._timeout) Mainloop.source_remove(this._timeout);
    }
};
function main(metadata, desklet_id) { return new QuentinClock(metadata, desklet_id); }
JSEOF

cat > "$DK/quentin-system@quentin-os/metadata.json" <<'JSONEOF'
{"uuid": "quentin-system@quentin-os", "name": "QUENTIN OS - Système", "description": "CPU, RAM, disque et réseau en direct", "max-instances": "1", "version": "1.0"}
JSONEOF
cat > "$DK/quentin-system@quentin-os/desklet.js" <<'JSEOF'
const Desklet = imports.ui.desklet;
const St = imports.gi.St;
const GLib = imports.gi.GLib;
const Gio = imports.gi.Gio;
const Mainloop = imports.mainloop;

const BAR_W = 200;
const LABEL = "font-size: 12px; color: #c084fc; font-weight: bold;";
const VALUE = "font-size: 12px; color: #e0f2fe;";

function readText(path) {
    try {
        let r = GLib.file_get_contents(path);
        return imports.byteArray.toString(r[1]);
    } catch (e) { return ""; }
}
function fmtBytes(n) {
    if (n >= 1073741824) return (n / 1073741824).toFixed(1) + " Go";
    if (n >= 1048576) return (n / 1048576).toFixed(0) + " Mo";
    return (n / 1024).toFixed(0) + " Ko";
}
function fmtSpeed(n) {
    if (n >= 1048576) return (n / 1048576).toFixed(1) + " Mo/s";
    return (n / 1024).toFixed(0) + " Ko/s";
}

function QuentinSystem(metadata, desklet_id) { this._init(metadata, desklet_id); }
QuentinSystem.prototype = {
    __proto__: Desklet.Desklet.prototype,
    _init: function (metadata, desklet_id) {
        Desklet.Desklet.prototype._init.call(this, metadata, desklet_id);
        this.box = new St.BoxLayout({ vertical: true, style: "background-color: rgba(11,16,48,0.80); border: 1px solid rgba(34,211,238,0.60); border-radius: 20px; padding: 16px 22px; width: 250px;" });
        this.title = new St.Label({ text: "SYSTÈME", style: "font-size: 13px; font-weight: bold; color: #22d3ee; padding-bottom: 6px;" });
        this.box.add_child(this.title);
        this.rows = {};
        let self = this;
        ["CPU", "RAM", "Disque"].forEach(function (name) { self.rows[name] = self._makeRow(name); });
        this.net = new St.Label({ text: "Réseau", style: VALUE + " padding-top: 8px;" });
        this.box.add_child(this.net);
        this.setContent(this.box);
        this.lastCpu = null;
        this.lastNet = null;
        this._update();
    },
    _makeRow: function (name) {
        let head = new St.BoxLayout({ style: "padding-top: 6px;" });
        let l = new St.Label({ text: name, style: LABEL, x_expand: true });
        let v = new St.Label({ text: "", style: VALUE });
        head.add_child(l);
        head.add_child(v);
        let track = new St.BoxLayout({ style: "background-color: rgba(255,255,255,0.14); border-radius: 4px; height: 6px; width: " + BAR_W + "px;" });
        let fill = new St.Widget({ style: "background-gradient-direction: horizontal; background-gradient-start: #22d3ee; background-gradient-end: #a855f7; border-radius: 4px; height: 6px;" });
        fill.set_width(2);
        track.add_child(fill);
        this.box.add_child(head);
        this.box.add_child(track);
        return { value: v, fill: fill };
    },
    _setRow: function (name, pct, text) {
        let r = this.rows[name];
        pct = Math.max(0, Math.min(100, pct));
        r.value.set_text(text);
        r.fill.set_width(Math.max(2, Math.round(BAR_W * pct / 100)));
    },
    _update: function () {
        try {
            // CPU
            let f = readText("/proc/stat").split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            let idle = f[3] + (f[4] || 0);
            let total = f.reduce(function (a, b) { return a + b; }, 0);
            if (this.lastCpu) {
                let dt = total - this.lastCpu.total, di = idle - this.lastCpu.idle;
                let pct = dt > 0 ? 100 * (dt - di) / dt : 0;
                this._setRow("CPU", pct, Math.round(pct) + " %");
            }
            this.lastCpu = { idle: idle, total: total };
            // RAM
            let mem = readText("/proc/meminfo");
            let mt = parseInt((mem.match(/MemTotal:\s+(\d+)/) || [0, 0])[1]) * 1024;
            let ma = parseInt((mem.match(/MemAvailable:\s+(\d+)/) || [0, 0])[1]) * 1024;
            if (mt > 0) this._setRow("RAM", 100 * (mt - ma) / mt, fmtBytes(mt - ma) + " / " + fmtBytes(mt));
            // Disque
            let info = Gio.File.new_for_path("/").query_filesystem_info("filesystem::size,filesystem::free", null);
            let size = info.get_attribute_uint64("filesystem::size");
            let free = info.get_attribute_uint64("filesystem::free");
            if (size > 0) this._setRow("Disque", 100 * (size - free) / size, fmtBytes(size - free) + " / " + fmtBytes(size));
            // Réseau
            let rx = 0, tx = 0;
            readText("/proc/net/dev").split("\n").slice(2).forEach(function (line) {
                let p = line.split(":");
                if (p.length < 2) return;
                if (p[0].trim() === "lo") return;
                let c = p[1].trim().split(/\s+/);
                rx += Number(c[0]) || 0;
                tx += Number(c[8]) || 0;
            });
            if (this.lastNet) {
                this.net.set_text("↓ " + fmtSpeed((rx - this.lastNet.rx) / 2) + "    ↑ " + fmtSpeed((tx - this.lastNet.tx) / 2));
            }
            this.lastNet = { rx: rx, tx: tx };
        } catch (e) {
            global.logError("quentin-system: " + e);
        }
        this._timeout = Mainloop.timeout_add_seconds(2, () => { this._update(); return false; });
    },
    on_desklet_removed: function () {
        if (this._timeout) Mainloop.source_remove(this._timeout);
    }
};
function main(metadata, desklet_id) { return new QuentinSystem(metadata, desklet_id); }
JSEOF

# Placement en haut à droite (modifiable ensuite à la souris)
DX=$(( ${W:-1920} - 300 )); [ "$DX" -lt 0 ] && DX=20
gs org.cinnamon enabled-desklets "['quentin-clock@quentin-os:0:$DX:70', 'quentin-system@quentin-os:1:$DX:230']"
gs org.cinnamon desklet-decorations 0

# ----------------------------------------------------------------------------
log "7/8 Écran de connexion (LightDM / slick-greeter)"
sudo tee /etc/lightdm/slick-greeter.conf >/dev/null <<EOF
[Greeter]
background=$SYS_BG/wallpaper-4k.png
draw-user-backgrounds=false
logo=$SYS_BG/logo-full.png
theme-name=$THEME
icon-theme-name=Papirus-Dark
font-name=Inter 11
draw-grid=false
show-hostname=true
show-a11y=false
EOF

if [ "$PLY" -eq 1 ]; then
  log "   Écran de démarrage (Plymouth) : remplace le logo Mint/Cinnamon"
  command -v plymouth-set-default-theme >/dev/null || sudo apt-get install -y plymouth plymouth-themes
  PT=/usr/share/plymouth/themes/quentin
  sudo mkdir -p "$PT"
  sudo cp "$DATA/ply-icon.png" "$PT/logo.png"
  sudo cp "$DATA"/bar-bg.png "$DATA"/bar-fill.png "$DATA"/ring-outer.png "$DATA"/ring-inner.png "$DATA"/halo.png "$DATA"/star.png "$DATA"/dot.png "$DATA"/logo-text.png "$PT/"
  sudo tee "$PT/quentin.plymouth" >/dev/null <<'EOF'
[Plymouth Theme]
Name=QUENTIN OS
Description=Ecran de demarrage QUENTIN OS
ModuleName=script
[script]
ImageDir=/usr/share/plymouth/themes/quentin
ScriptFile=/usr/share/plymouth/themes/quentin/quentin.script
EOF
  sudo tee "$PT/quentin.script" >/dev/null <<'EOF'
# QUENTIN OS : écran de démarrage animé
Window.SetBackgroundTopColor(0.02, 0.03, 0.09);
Window.SetBackgroundBottomColor(0.16, 0.06, 0.37);
W = Window.GetWidth();
H = Window.GetHeight();
cx = W / 2;
cy = H / 2 - 60;

# Champ d'étoiles qui scintillent et dérivent lentement
starimg = Image("star.png");
for (i = 0; i < 80; i++) {
  stars[i].sprite = Sprite(starimg);
  stars[i].x = Math.Random() * W;
  stars[i].y = Math.Random() * H;
  stars[i].phase = Math.Random() * 6.28;
  stars[i].speed = 0.03 + Math.Random() * 0.06;
  stars[i].drift = 0.05 + Math.Random() * 0.15;
  stars[i].sprite.SetPosition(stars[i].x, stars[i].y, 1);
}

# Halo lumineux derrière le logo
haloimg = Image("halo.png");
halo = Sprite(haloimg);
halo.SetPosition(cx - haloimg.GetWidth() / 2, cy - haloimg.GetHeight() / 2, 2);
halo.SetOpacity(0);

# Anneaux qui tournent en sens inverse
ring1img = Image("ring-outer.png");
ring1 = Sprite(ring1img);
ring1.SetPosition(cx - ring1img.GetWidth() / 2, cy - ring1img.GetHeight() / 2, 5);
ring2img = Image("ring-inner.png");
ring2 = Sprite(ring2img);
ring2.SetPosition(cx - ring2img.GetWidth() / 2, cy - ring2img.GetHeight() / 2, 5);
ring1.SetOpacity(0);
ring2.SetOpacity(0);

# Logo Q au centre et nom en dessous
logoimg = Image("logo.png");
logo = Sprite(logoimg);
logo.SetPosition(cx - logoimg.GetWidth() / 2, cy - logoimg.GetHeight() / 2, 10);
logo.SetOpacity(0);
textimg = Image("logo-text.png");
logotext = Sprite(textimg);
ty = cy + 195;
logotext.SetPosition(cx - textimg.GetWidth() / 2, ty, 10);
logotext.SetOpacity(0);

# Barre de progression
bgimg = Image("bar-bg.png");
barbg = Sprite(bgimg);
bx = cx - bgimg.GetWidth() / 2;
by = ty + 125;
barbg.SetPosition(bx, by, 10);
barbg.SetOpacity(0);
fillimg = Image("bar-fill.png");
barfill = Sprite();
barfill.SetPosition(bx, by, 11);

frame = 0;
progressvalue = 0;
shown = 0;

fun refresh() {
  frame++;
  # apparition en fondu (environ 1,2 s)
  fade = frame / 60;
  if (fade > 1) fade = 1;
  pulse = 0.5 + 0.5 * Math.Sin(frame / 18);
  halo.SetOpacity(fade * (0.55 + 0.45 * pulse));
  logo.SetOpacity(fade);
  logotext.SetOpacity(fade);
  barbg.SetOpacity(fade);
  ring1.SetOpacity(fade);
  ring2.SetOpacity(fade);
  ring1.SetImage(ring1img.Rotate(frame * 0.035));
  ring2.SetImage(ring2img.Rotate(-frame * 0.055));
  for (i = 0; i < 80; i++) {
    stars[i].sprite.SetOpacity(0.25 + 0.75 * (0.5 + 0.5 * Math.Sin(frame * stars[i].speed + stars[i].phase)));
    stars[i].x = stars[i].x - stars[i].drift;
    if (stars[i].x < -6) stars[i].x = W;
    stars[i].sprite.SetPosition(stars[i].x, stars[i].y, 1);
  }
  # la barre avance toujours un peu même si le système ne donne pas de progression
  shown = shown + (progressvalue - shown) * 0.08;
  w = Math.Int(fillimg.GetWidth() * shown);
  if (w < 4) w = 4;
  barfill.SetImage(fillimg.Scale(w, fillimg.GetHeight()));
}
Plymouth.SetRefreshFunction(refresh);

fun progress(time, p) {
  progressvalue = p;
}
Plymouth.SetBootProgressFunction(progress);

# Mot de passe (disque chiffré) : étiquette + points
pwlabelimg = Image.Text("Mot de passe", 0.88, 0.95, 1.0);
pwlabel = Sprite(pwlabelimg);
pwlabel.SetPosition(cx - pwlabelimg.GetWidth() / 2, by + 40, 20);
pwlabel.SetOpacity(0);
dotimg = Image("dot.png");
for (i = 0; i < 32; i++) {
  pwdots[i] = Sprite(dotimg);
  pwdots[i].SetPosition(cx - 16 * 11 + i * 22, by + 75, 20);
  pwdots[i].SetOpacity(0);
}
fun password_cb(prompt, bullets) {
  pwlabel.SetOpacity(1);
  for (i = 0; i < 32; i++) {
    if (i < bullets) pwdots[i].SetOpacity(1);
    else pwdots[i].SetOpacity(0);
  }
}
Plymouth.SetDisplayPasswordFunction(password_cb);
fun normal_cb() {
  pwlabel.SetOpacity(0);
  for (i = 0; i < 32; i++) pwdots[i].SetOpacity(0);
}
Plymouth.SetDisplayNormalFunction(normal_cb);
EOF
  sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$PT/quentin.plymouth" 200 || true
  sudo update-alternatives --set default.plymouth "$PT/quentin.plymouth" || true
  sudo plymouth-set-default-theme quentin 2>/dev/null || true
  sudo update-initramfs -u
fi

log "   Menu de démarrage (GRUB) : fond et couleurs QUENTIN OS"
sudo mkdir -p /etc/default/grub.d
sudo tee /etc/default/grub.d/99-quentin.cfg >/dev/null <<EOF
GRUB_DISTRIBUTOR="QUENTIN OS"
GRUB_THEME=""
GRUB_BACKGROUND="$SYS_BG/wallpaper-fhd.png"
GRUB_COLOR_NORMAL="light-cyan/black"
GRUB_COLOR_HIGHLIGHT="white/magenta"
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
EOF
sudo update-grub || log "  (update-grub a échoué : le menu GRUB reste inchangé)"

# ----------------------------------------------------------------------------
log "8/8 Redémarrage de Cinnamon et finition de la barre des tâches (Q seul, sans texte)"
nohup cinnamon --replace >/dev/null 2>&1 &
disown || true
for _ in $(seq 1 45); do
  ls "$HOME"/.config/cinnamon/spices/menu@cinnamon.org/*.json >/dev/null 2>&1 && break
  sleep 1
done
sleep 3
python3 - "$SYS_BG/logo-icon.svg" <<'PYEOF'
import glob, json, os, sys
icon = sys.argv[1]
def patch(applet, changes):
    files = glob.glob(os.path.expanduser("~/.config/cinnamon/spices/%s/*.json" % applet))
    if not files:
        print("Réglages introuvables pour", applet)
    for f in files:
        try:
            d = json.load(open(f))
            for k, v in changes.items():
                if k in d:
                    d[k]["value"] = v
                else:
                    print("Clé absente (version de Cinnamon différente) :", applet, k)
            json.dump(d, open(f, "w"), indent=4)
            print("OK :", f)
        except Exception as e:
            print("Non modifié :", f, e)
patch("menu@cinnamon.org", {"menu-icon-custom": True, "menu-icon": icon, "menu-label": ""})
patch("grouped-window-list@cinnamon.org", {"pinned-apps": ["firefox.desktop", "nemo.desktop", "org.gnome.Terminal.desktop", "vlc.desktop", "org.gnome.Rhythmbox3.desktop"]})
PYEOF
nohup cinnamon --replace >/dev/null 2>&1 &
disown || true

log "Terminé. QUENTIN OS est appliqué."
log "Déconnectez-vous puis reconnectez-vous pour tout voir (écran de connexion inclus)."
log "Widgets : glissez-les à la souris ; clic droit > Retirer pour les supprimer (clic droit sur le bureau > Ajouter des desklets pour les remettre)."
log "Pour revenir en arrière : bash $(basename "$0") uninstall"
