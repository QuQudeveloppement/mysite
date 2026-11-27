#!/usr/bin/env bash
# ============================================================================
#  QUENTIN OS pour Linux Mint Cinnamon
#  Remplace l'apparence complète du bureau : fond, thème GTK/Cinnamon (verre,
#  bordures cyan/violet), icônes, barre des tâches, menu, widgets, terminal,
#  écran de connexion. Réversible.
#
#  Usage :  bash quentin-os-mint.sh [install|uninstall] [--no-plymouth]
#  (écran de démarrage + menu GRUB QUENTIN OS inclus par défaut)
#  À lancer en utilisateur normal (sudo sera demandé), dans une session Cinnamon.
# ============================================================================
set -euo pipefail

ACTION="install"; PLY=1
for a in "$@"; do case "$a" in install|uninstall) ACTION="$a";; --plymouth) PLY=1;; --no-plymouth) PLY=0;; esac; done

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
sudo apt-get update -qq
sudo apt-get install -y librsvg2-bin conky-all papirus-icon-theme fonts-inter python3 dconf-cli

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
[ -f "$TMP/$THEME/cinnamon/cinnamon.css" ] && printf '%s\n' "$CINCSS" >> "$TMP/$THEME/cinnamon/cinnamon.css"
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
gs org.cinnamon panels-height "['1:48']"
gs org.cinnamon panels-autohide "['1:false']"
gs org.cinnamon panel-zone-icon-sizes '[{"panelId": 1, "left": 28, "center": 28, "right": 22}]'
gs org.cinnamon panel-zone-symbolic-icon-sizes '[{"panelId": 1, "left": 24, "center": 24, "right": 20}]'
gs org.cinnamon enabled-applets "['panel1:left:0:menu@cinnamon.org:0', 'panel1:left:1:grouped-window-list@cinnamon.org:1', 'panel1:right:0:systray@cinnamon.org:2', 'panel1:right:1:notifications@cinnamon.org:3', 'panel1:right:2:keyboard@cinnamon.org:4', 'panel1:right:3:network@cinnamon.org:5', 'panel1:right:4:sound@cinnamon.org:6', 'panel1:right:5:power@cinnamon.org:7', 'panel1:right:6:calendar@cinnamon.org:8']"
gs org.cinnamon favorite-apps "['firefox.desktop', 'nemo.desktop', 'org.gnome.Terminal.desktop', 'mintinstall.desktop', 'cinnamon-settings.desktop', 'org.gnome.Calculator.desktop', 'xed.desktop']"
gs org.nemo.desktop show-desktop-icons true

# Terminal : fond verre bleu nuit, texte cyan clair
if command -v gnome-terminal >/dev/null; then
  PID=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'" || true)
  if [ -n "$PID" ]; then
    P="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PID/"
    gsettings set "$P" use-theme-colors false || true
    gsettings set "$P" background-color '#0B1030' || true
    gsettings set "$P" foreground-color '#E0F2FE' || true
    gsettings set "$P" use-theme-transparency false || true
    gsettings set "$P" use-transparent-background true || true
    gsettings set "$P" background-transparency-percent 18 || true
    gsettings set "$P" palette "['#0B1030','#F43F5E','#34D399','#FBBF24','#38BDF8','#A855F7','#22D3EE','#E0F2FE','#475569','#FB7185','#6EE7B7','#FCD34D','#7DD3FC','#C084FC','#67E8F9','#FFFFFF']" || true
    gsettings set "$P" cursor-background-color '#22D3EE' || true
    gsettings set "$P" cursor-colors-set true || true
  fi
fi

# ----------------------------------------------------------------------------
log "6/8 Widgets système sur le bureau (Conky : heure, CPU, RAM, disque, réseau)"
mkdir -p "$HOME/.config/conky" "$HOME/.config/autostart"
cat > "$HOME/.config/conky/quentin.conf" <<'EOF'
conky.config = {
  alignment='top_right', gap_x=36, gap_y=56, minimum_width=270, maximum_width=270,
  own_window=true, own_window_type='desktop', own_window_transparent=false,
  own_window_argb_visual=true, own_window_argb_value=120, own_window_colour='0b1030',
  own_window_hints='undecorated,below,sticky,skip_taskbar,skip_pager',
  double_buffer=true, update_interval=2, use_xft=true, font='Inter:size=10',
  default_color='e0f2fe', color1='22d3ee', color2='c084fc', draw_borders=true,
  border_inner_margin=18, border_width=1, default_outline_color='22d3ee',
};
conky.text = [[
${color1}${font Inter:bold:size=24}${time %H:%M}${font}
${color}${time %A %d %B %Y}

${color2}SYSTÈME${color}
CPU   ${cpu}%  ${color1}${cpubar 6}${color}
RAM   ${memperc}%  ${color1}${membar 6}${color}
${mem} / ${memmax}
Disque /   ${fs_used_perc /}%  ${color1}${fs_bar 6 /}${color}
${fs_used /} / ${fs_size /}

${color2}RÉSEAU${color}
↓ ${downspeed}   ↑ ${upspeed}

${color2}PROCESSUS${color}
${top name 1}  ${top cpu 1}%
${top name 2}  ${top cpu 2}%
${top name 3}  ${top cpu 3}%
]];
EOF
cat > "$HOME/.config/autostart/quentin-conky.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Widgets QUENTIN OS
Exec=sh -c "sleep 4 && conky -c $HOME/.config/conky/quentin.conf"
X-GNOME-Autostart-enabled=true
EOF
pkill conky 2>/dev/null || true
( nohup conky -c "$HOME/.config/conky/quentin.conf" >/dev/null 2>&1 & ) || true

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
  sudo cp "$DATA/logo-full.png" "$PT/logo.png"
  sudo cp "$DATA/bar-bg.png" "$DATA/bar-fill.png" "$PT/"
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
Window.SetBackgroundTopColor(0.02, 0.03, 0.09);
Window.SetBackgroundBottomColor(0.16, 0.06, 0.37);

logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);
lx = Window.GetWidth() / 2 - logo.image.GetWidth() / 2;
ly = Window.GetHeight() / 2 - logo.image.GetHeight() / 2 - 30;
logo.sprite.SetPosition(lx, ly, 10);

bar.bg.image = Image("bar-bg.png");
bar.bg.sprite = Sprite(bar.bg.image);
bx = Window.GetWidth() / 2 - bar.bg.image.GetWidth() / 2;
by = ly + logo.image.GetHeight() + 60;
bar.bg.sprite.SetPosition(bx, by, 10);

bar.fill.image = Image("bar-fill.png");
bar.fill.sprite = Sprite();
bar.fill.sprite.SetPosition(bx, by, 11);

global.i = 0;
fun refresh() {
  logo.sprite.SetOpacity(0.75 + 0.25 * Math.Sin(global.i / 14));
  global.i++;
}
Plymouth.SetRefreshFunction(refresh);

fun progress(time, p) {
  w = Math.Int(bar.fill.image.GetWidth() * p);
  if (w < 1) w = 1;
  bar.fill.sprite.SetImage(bar.fill.image.Scale(w, bar.fill.image.GetHeight()));
}
Plymouth.SetBootProgressFunction(progress);
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
log "8/8 Redémarrage de Cinnamon et logo du menu"
nohup cinnamon --replace >/dev/null 2>&1 &
disown || true
sleep 6
# Logo QUENTIN OS sur le bouton du menu (le fichier de réglages n'existe qu'après le 1er chargement)
python3 - "$SYS_BG/logo-icon.svg" <<'PYEOF'
import glob, json, os, sys
icon = sys.argv[1]
for f in glob.glob(os.path.expanduser("~/.config/cinnamon/spices/menu@cinnamon.org/*.json")):
    try:
        d = json.load(open(f))
        for k, v in (("menu-icon-custom", True), ("menu-icon", icon), ("menu-label", "QUENTIN OS")):
            if k in d: d[k]["value"] = v
        json.dump(d, open(f, "w"), indent=4)
        print("Menu mis à jour :", f)
    except Exception as e:
        print("Menu non modifié :", e)
PYEOF
nohup cinnamon --replace >/dev/null 2>&1 &
disown || true

log "Terminé. QUENTIN OS est appliqué."
log "Déconnectez-vous puis reconnectez-vous pour tout voir (écran de connexion inclus)."
log "Pour revenir en arrière : bash $(basename "$0") uninstall"
