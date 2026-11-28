#!/usr/bin/env bash
# ============================================================================
#  QUENTIN OS pour Linux Mint Cinnamon
#  Remplace l'apparence complète du bureau : fond, thème GTK/Cinnamon (verre,
#  bordures cyan/violet), icônes, barre des tâches, menu, widgets, terminal,
#  écran de connexion. Réversible.
#
#  Usage :  bash quentin-os-mint.sh [install|uninstall|repair-boot] [--plymouth (expérimental)] [--no-media]
#  repair-boot : annule SEULEMENT le menu GRUB et l'écran de démarrage (utilisable en root depuis une console)
#  À lancer en utilisateur normal (sudo sera demandé), dans une session Cinnamon.
# ============================================================================
set -euo pipefail

ACTION="install"; PLY=0; MEDIA=1
for a in "$@"; do case "$a" in install|uninstall|repair-boot) ACTION="$a";; --plymouth) PLY=1;; --no-plymouth) PLY=0;; --no-media) MEDIA=0;; esac; done

DATA="$HOME/.local/share/quentin-os"
BACKUP="$HOME/.quentin-os-backup"
THEME="Quentin-Glass"
RENAME_FILES="/etc/os-release /etc/lsb-release /etc/linuxmint/info /usr/share/xsessions/cinnamon.desktop /usr/share/xsessions/cinnamon2d.desktop"
SYS_BG="/usr/share/backgrounds/quentin-os"

log() { printf '\033[1;36m[QUENTIN OS]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERREUR]\033[0m %s\n' "$*" >&2; exit 1; }

if [ "$ACTION" = "repair-boot" ]; then
  SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
  log "Réparation du démarrage : retrait du fond GRUB et du thème Plymouth QUENTIN OS"
  $SUDO rm -f /etc/default/grub.d/99-quentin.cfg
  if [ -d /usr/share/plymouth/themes/quentin ]; then
    $SUDO update-alternatives --remove default.plymouth /usr/share/plymouth/themes/quentin/quentin.plymouth 2>/dev/null || true
    ORIG="$(cat "$HOME/.quentin-os-backup/plymouth.orig" 2>/dev/null || true)"
    [ -n "$ORIG" ] || ORIG="$(plymouth-set-default-theme -l 2>/dev/null | grep -m1 -E 'mint-logo|ubuntu-logo|bgrt|spinner' || true)"
    [ -n "$ORIG" ] && $SUDO plymouth-set-default-theme "$ORIG" || true
    $SUDO rm -rf /usr/share/plymouth/themes/quentin
  fi
  $SUDO update-initramfs -u -k all
  $SUDO update-grub
  log "Terminé. Redémarrez : le démarrage est revenu à l'état d'origine."
  exit 0
fi

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
  rm -f "$HOME"/.local/share/applications/quentin-*.desktop
  grep -l "QUENTIN-OS-OVERRIDE" "$HOME"/.local/share/applications/*.desktop 2>/dev/null | xargs -r rm -f
  rm -rf "$HOME/.local/share/icons/Quentin-Icons"
  for f in $RENAME_FILES; do
    d="$BACKUP/rename/$(echo "$f" | tr / _)"
    [ -f "$d" ] && sudo cp "$d" "$f" || true
  done
  sudo rm -f /etc/default/grub.d/98-quentin-name.cfg
  sudo update-grub >/dev/null 2>&1 || true
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
log "3b/8 Icônes QUENTIN OS et applications QUENTIN OS (Paramètres, Fichiers, Moniteur, Notes, Calculatrice)"
mkdir -p "$DATA/apps" "$HOME/.local/share/applications"
cat > "$DATA/apps/quentin_apps.py" <<'QAPPSEOF'
#!/usr/bin/env python3
"""Applications QUENTIN OS : Paramètres, Fichiers, Moniteur système, Notes, Calculatrice."""
import ast, operator, os, platform, shutil, signal, subprocess, sys, time
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gio, GLib, Gdk

HOME = os.path.expanduser("~")
SYS_BG = "/usr/share/backgrounds/quentin-os"
LOGO = SYS_BG + "/logo-full.png"


def gset(schema):
    src = Gio.SettingsSchemaSource.get_default()
    if src and src.lookup(schema, True):
        return Gio.Settings.new(schema)
    return None


def info_box(parent, text, kind=Gtk.MessageType.INFO):
    d = Gtk.MessageDialog(transient_for=parent, modal=True, message_type=kind, buttons=Gtk.ButtonsType.OK, text=text)
    d.run()
    d.destroy()


def ask(parent, text):
    d = Gtk.MessageDialog(transient_for=parent, modal=True, message_type=Gtk.MessageType.QUESTION, buttons=Gtk.ButtonsType.YES_NO, text=text)
    r = d.run()
    d.destroy()
    return r == Gtk.ResponseType.YES


def prompt(parent, title, default=""):
    d = Gtk.Dialog(title=title, transient_for=parent, modal=True)
    d.add_buttons("Annuler", Gtk.ResponseType.CANCEL, "OK", Gtk.ResponseType.OK)
    e = Gtk.Entry(text=default, activates_default=True)
    d.set_default_response(Gtk.ResponseType.OK)
    d.get_content_area().pack_start(e, True, True, 12)
    d.get_content_area().set_border_width(12)
    d.show_all()
    r = d.run()
    txt = e.get_text().strip()
    d.destroy()
    return txt if r == Gtk.ResponseType.OK and txt else None


def run_detached(cmd):
    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except Exception:
        return False


def page(title):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=24)
    lbl = Gtk.Label(xalign=0)
    lbl.set_markup("<span size='x-large' weight='bold'>%s</span>" % title)
    box.pack_start(lbl, False, False, 4)
    sc = Gtk.ScrolledWindow()
    sc.add(box)
    return sc, box


def row(label, widget):
    r = Gtk.Box(spacing=12)
    l = Gtk.Label(label=label, xalign=0)
    l.set_size_request(240, -1)
    r.pack_start(l, False, False, 0)
    r.pack_start(widget, False, False, 0)
    return r


# ----------------------------------------------------------------------------
class SettingsApp(Gtk.Window):
    def __init__(self):
        super().__init__(title="Paramètres QUENTIN OS")
        self.set_default_size(900, 600)
        self.interface = gset("org.cinnamon.desktop.interface")
        self.bg = gset("org.cinnamon.desktop.background")
        self.cin = gset("org.cinnamon")
        self.saver = gset("org.cinnamon.desktop.screensaver")
        self.theme = gset("org.cinnamon.theme")
        self.wm = gset("org.cinnamon.desktop.wm.preferences")
        box = Gtk.Box()
        self.add(box)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        side = Gtk.StackSidebar()
        side.set_stack(self.stack)
        side.set_size_request(210, -1)
        box.pack_start(side, False, False, 0)
        box.pack_start(self.stack, True, True, 0)
        for name, title, fn in (("app", "Apparence", self.p_appearance), ("bar", "Barre des tâches", self.p_taskbar),
                                ("lock", "Écran de verrouillage", self.p_lock), ("sys", "Système", self.p_system),
                                ("about", "À propos", self.p_about)):
            self.stack.add_titled(fn(), name, title)

    # -- helpers
    def _list_themes(self, dirs, need):
        names = set()
        for d in dirs:
            if os.path.isdir(d):
                for n in os.listdir(d):
                    if os.path.exists(os.path.join(d, n, need)):
                        names.add(n)
        return sorted(names)

    def _combo(self, items, current, cb):
        c = Gtk.ComboBoxText()
        for i in items:
            c.append_text(i)
        if current in items:
            c.set_active(items.index(current))
        c.connect("changed", lambda w: cb(w.get_active_text()) if w.get_active_text() else None)
        return c

    # -- pages
    def p_appearance(self):
        sc, box = page("Apparence")
        fc = Gtk.FileChooserButton(title="Choisir un fond d'écran", action=Gtk.FileChooserAction.OPEN)
        flt = Gtk.FileFilter()
        flt.set_name("Images")
        flt.add_mime_type("image/*")
        fc.add_filter(flt)
        if self.bg:
            fc.connect("file-set", lambda w: self.bg.set_string("picture-uri", w.get_uri()))
        box.pack_start(row("Fond d'écran", fc), False, False, 0)
        b = Gtk.Button(label="Remettre le fond QUENTIN OS")
        def default_bg(_):
            w = Gdk.Screen.get_default().get_width()
            n = "4k" if w >= 3200 else "2k" if w >= 2200 else "fhd" if w >= 1700 else "hd"
            if self.bg:
                self.bg.set_string("picture-uri", "file://%s/wallpaper-%s.png" % (SYS_BG, n))
        b.connect("clicked", default_bg)
        box.pack_start(row("", b), False, False, 0)
        if self.interface:
            themes = self._list_themes(["/usr/share/themes", os.path.join(HOME, ".themes")], "gtk-3.0")
            def set_theme(n):
                self.interface.set_string("gtk-theme", n)
                if self.wm: self.wm.set_string("theme", n)
                if self.theme and os.path.isdir("/usr/share/themes/%s/cinnamon" % n):
                    self.theme.set_string("name", n)
            box.pack_start(row("Thème des fenêtres", self._combo(themes, self.interface.get_string("gtk-theme"), set_theme)), False, False, 0)
            icons = self._list_themes(["/usr/share/icons", os.path.join(HOME, ".local/share/icons")], "index.theme")
            box.pack_start(row("Thème d'icônes", self._combo(icons, self.interface.get_string("icon-theme"), lambda n: self.interface.set_string("icon-theme", n))), False, False, 0)
            fb = Gtk.FontButton()
            fb.set_font(self.interface.get_string("font-name"))
            fb.connect("font-set", lambda w: self.interface.set_string("font-name", w.get_font()))
            box.pack_start(row("Police de l'interface", fb), False, False, 0)
        if self.cin:
            sw = Gtk.Switch()
            self.cin.bind("desktop-effects", sw, "active", Gio.SettingsBindFlags.DEFAULT)
            box.pack_start(row("Animations et effets", sw), False, False, 0)
        return sc

    def _desklets(self):
        return list(self.cin.get_strv("enabled-desklets")) if self.cin else []

    def _toggle_desklet(self, uuid, on, y):
        cur = [d for d in self._desklets() if not d.startswith(uuid + ":")]
        if on:
            x = max(20, Gdk.Screen.get_default().get_width() - 300)
            ids = [int(d.split(":")[1]) for d in self._desklets() if d.split(":")[1].isdigit()]
            cur.append("%s:%d:%d:%d" % (uuid, (max(ids) + 1) if ids else 0, x, y))
        self.cin.set_strv("enabled-desklets", cur)

    def p_taskbar(self):
        sc, box = page("Barre des tâches et widgets")
        if not self.cin:
            box.pack_start(Gtk.Label(label="Réglages Cinnamon indisponibles."), False, False, 0)
            return sc
        h = 56
        for p in self.cin.get_strv("panels-height"):
            if p.startswith("1:"): h = int(p.split(":")[1])
        spin = Gtk.SpinButton.new_with_range(32, 96, 2)
        spin.set_value(h)
        spin.connect("value-changed", lambda w: self.cin.set_strv("panels-height", ["1:%d" % int(w.get_value())]))
        box.pack_start(row("Hauteur de la barre (px)", spin), False, False, 0)
        pos = "bottom"
        for p in self.cin.get_strv("panels-enabled"):
            if p.startswith("1:"): pos = p.split(":")[2]
        box.pack_start(row("Position", self._combo(["bottom", "top"], pos, lambda v: self.cin.set_strv("panels-enabled", ["1:0:" + v]))), False, False, 0)
        ah = Gtk.Switch()
        ah.set_active(any(p == "1:true" for p in self.cin.get_strv("panels-autohide")))
        ah.connect("notify::active", lambda w, _: self.cin.set_strv("panels-autohide", ["1:true" if w.get_active() else "1:false"]))
        box.pack_start(row("Masquer automatiquement", ah), False, False, 0)
        for uuid, label, y in (("quentin-clock@quentin-os", "Widget horloge", 70), ("quentin-system@quentin-os", "Widget système", 230)):
            sw = Gtk.Switch()
            sw.set_active(any(d.startswith(uuid + ":") for d in self._desklets()))
            sw.connect("notify::active", lambda w, _, u=uuid, yy=y: self._toggle_desklet(u, w.get_active(), yy))
            box.pack_start(row(label, sw), False, False, 0)
        t = Gtk.Label(xalign=0, wrap=True, label="Les widgets se déplacent à la souris sur le bureau.")
        box.pack_start(t, False, False, 0)
        rb = Gtk.Button(label="Recharger l'interface (barre, menu)")
        rb.connect("clicked", lambda _: run_detached(["cinnamon", "--replace"]))
        box.pack_start(row("", rb), False, False, 0)
        return sc

    def p_lock(self):
        sc, box = page("Écran de verrouillage")
        if not self.saver:
            box.pack_start(Gtk.Label(label="Réglages indisponibles."), False, False, 0)
            return sc
        for key, label in (("default-message", "Message affiché"), ("time-format", "Format de l'heure"), ("date-format", "Format de la date")):
            e = Gtk.Entry(width_chars=28)
            try:
                self.saver.bind(key, e, "text", Gio.SettingsBindFlags.DEFAULT)
            except Exception:
                continue
            box.pack_start(row(label, e), False, False, 0)
        for key, label in (("use-custom-format", "Formats personnalisés"), ("show-clock", "Afficher l'horloge")):
            sw = Gtk.Switch()
            try:
                self.saver.bind(key, sw, "active", Gio.SettingsBindFlags.DEFAULT)
            except Exception:
                continue
            box.pack_start(row(label, sw), False, False, 0)
        b = Gtk.Button(label="Verrouiller maintenant")
        b.connect("clicked", lambda _: run_detached(["cinnamon-screensaver-command", "-l"]))
        box.pack_start(row("", b), False, False, 0)
        return sc

    def p_system(self):
        sc, box = page("Système")
        try:
            osn = [l.split("=", 1)[1].strip().strip('"') for l in open("/etc/os-release") if l.startswith("PRETTY_NAME=")][0]
        except Exception:
            osn = "QUENTIN OS"
        mem = ""
        try:
            kb = int([l for l in open("/proc/meminfo") if l.startswith("MemTotal")][0].split()[1])
            mem = "%.1f Go" % (kb / 1048576)
        except Exception:
            pass
        cpu = ""
        try:
            cpu = [l.split(":", 1)[1].strip() for l in open("/proc/cpuinfo") if l.startswith("model name")][0]
        except Exception:
            pass
        for k, v in (("Système", osn), ("Noyau", platform.release()), ("Processeur", cpu), ("Mémoire", mem), ("Nom de la machine", platform.node())):
            box.pack_start(row(k, Gtk.Label(label=v, xalign=0, selectable=True)), False, False, 0)
        box.pack_start(Gtk.Separator(), False, False, 6)
        box.pack_start(Gtk.Label(xalign=0, wrap=True, label="Réglages matériels : ces boutons ouvrent les modules système (réseau, son, écrans, imprimantes, mises à jour)."), False, False, 0)
        grid = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=3, column_spacing=10, row_spacing=10)
        mods = (("Réseau et Wi-Fi", ["nm-connection-editor"]), ("Son", ["pavucontrol"]), ("Écrans", ["cinnamon-settings", "display"]),
                ("Clavier", ["cinnamon-settings", "keyboard"]), ("Souris", ["cinnamon-settings", "mouse"]), ("Alimentation", ["cinnamon-settings", "power"]),
                ("Date et heure", ["cinnamon-settings", "calendar"]), ("Utilisateurs", ["cinnamon-settings", "user"]), ("Bluetooth", ["blueman-manager"]),
                ("Imprimantes", ["system-config-printer"]), ("Mises à jour", ["mintupdate"]), ("Applications au démarrage", ["cinnamon-session-properties"]))
        for label, cmd in mods:
            b = Gtk.Button(label=label)
            b.set_sensitive(shutil.which(cmd[0]) is not None)
            b.connect("clicked", lambda _, c=cmd: run_detached(c))
            grid.add(b)
        box.pack_start(grid, False, False, 0)
        return sc

    def p_about(self):
        sc, box = page("À propos")
        if os.path.exists(LOGO):
            box.pack_start(Gtk.Image.new_from_file(LOGO), False, False, 10)
        box.pack_start(Gtk.Label(xalign=0, wrap=True, label="QUENTIN OS 0.2\nBureau personnalisé basé sur Linux Mint.\nApplications QUENTIN OS : Paramètres, Fichiers, Moniteur système, Notes, Calculatrice."), False, False, 0)
        return sc


# ----------------------------------------------------------------------------
class FilesApp(Gtk.Window):
    def __init__(self, start=None):
        super().__init__(title="Fichiers QUENTIN OS")
        self.set_default_size(980, 620)
        self.cwd = HOME
        self.hist = []
        self.show_hidden = False
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(v)
        bar = Gtk.Box(spacing=6, margin=8)
        def btn(label, cb, tip):
            b = Gtk.Button(label=label, tooltip_text=tip)
            b.connect("clicked", cb)
            bar.pack_start(b, False, False, 0)
            return b
        btn("←", lambda _: self.back(), "Précédent")
        btn("↑", lambda _: self.load(os.path.dirname(self.cwd)), "Dossier parent")
        btn("Accueil", lambda _: self.load(HOME), "Dossier personnel")
        self.entry = Gtk.Entry()
        self.entry.connect("activate", lambda e: self.load(os.path.expanduser(e.get_text())))
        bar.pack_start(self.entry, True, True, 0)
        btn("Nouveau dossier", lambda _: self.new_folder(), "Créer un dossier")
        btn("Renommer", lambda _: self.rename(), "Renommer la sélection")
        btn("Corbeille", lambda _: self.trash(), "Mettre la sélection à la corbeille")
        tg = Gtk.ToggleButton(label="Fichiers cachés")
        tg.connect("toggled", lambda w: self._hidden(w.get_active()))
        bar.pack_start(tg, False, False, 0)
        v.pack_start(bar, False, False, 0)
        paned = Gtk.Paned()
        v.pack_start(paned, True, True, 0)
        places = Gtk.ListBox()
        places.set_size_request(180, -1)
        for name, sub in (("Accueil", ""), ("Bureau", "Desktop"), ("Documents", "Documents"), ("Téléchargements", "Téléchargements"),
                          ("Images", "Images"), ("Musique", "Musique"), ("Vidéos", "Vidéos")):
            path = os.path.join(HOME, sub) if sub else HOME
            if not os.path.isdir(path):
                alt = os.path.join(HOME, {"Téléchargements": "Downloads", "Images": "Pictures", "Musique": "Music", "Vidéos": "Videos"}.get(sub, sub))
                if os.path.isdir(alt):
                    path = alt
                else:
                    continue
            r = Gtk.ListBoxRow()
            r.path = path
            r.add(Gtk.Label(label=name, xalign=0, margin=8))
            places.add(r)
        places.connect("row-activated", lambda lb, r: self.load(r.path))
        paned.pack1(places, False, False)
        self.store = Gtk.ListStore(Gio.Icon, str, str, str, str, bool)
        self.tree = Gtk.TreeView(model=self.store)
        c = Gtk.TreeViewColumn("Nom")
        pix = Gtk.CellRendererPixbuf()
        c.pack_start(pix, False)
        c.add_attribute(pix, "gicon", 0)
        txt = Gtk.CellRendererText()
        c.pack_start(txt, True)
        c.add_attribute(txt, "text", 1)
        c.set_expand(True)
        self.tree.append_column(c)
        for i, t in ((2, "Taille"), (3, "Modifié")):
            self.tree.append_column(Gtk.TreeViewColumn(t, Gtk.CellRendererText(), text=i))
        self.tree.connect("row-activated", lambda t, p, c: self.open_row(p))
        self.tree.connect("button-press-event", self.on_click)
        self.tree.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
        sc = Gtk.ScrolledWindow()
        sc.add(self.tree)
        paned.pack2(sc, True, False)
        self.status = Gtk.Label(xalign=0, margin=6)
        v.pack_start(self.status, False, False, 0)
        self.load(start if start and os.path.isdir(start) else HOME, push=False)

    def _hidden(self, on):
        self.show_hidden = on
        self.load(self.cwd, push=False)

    def load(self, path, push=True):
        path = os.path.abspath(path)
        if not os.path.isdir(path):
            return
        try:
            entries = list(os.scandir(path))
        except PermissionError:
            info_box(self, "Accès refusé à ce dossier.", Gtk.MessageType.WARNING)
            return
        if push and path != self.cwd:
            self.hist.append(self.cwd)
        self.cwd = path
        self.entry.set_text(path)
        self.store.clear()
        n = 0
        for e in sorted(entries, key=lambda e: (not e.is_dir(), e.name.lower())):
            if e.name.startswith(".") and not self.show_hidden:
                continue
            try:
                f = Gio.File.new_for_path(e.path)
                icon = f.query_info("standard::icon", 0, None).get_icon()
                st = e.stat()
                isdir = e.is_dir()
                self.store.append([icon, e.name, "" if isdir else GLib.format_size(st.st_size), time.strftime("%d/%m/%Y %H:%M", time.localtime(st.st_mtime)), e.path, isdir])
                n += 1
            except Exception:
                continue
        self.status.set_text("%d élément(s)" % n)
        self.set_title("Fichiers QUENTIN OS - " + (os.path.basename(path) or "/"))

    def back(self):
        if self.hist:
            self.load(self.hist.pop(), push=False)

    def open_row(self, treepath):
        it = self.store.get_iter(treepath)
        path, isdir = self.store[it][4], self.store[it][5]
        if isdir:
            self.load(path)
        else:
            try:
                Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(path).get_uri(), None)
            except Exception as e:
                info_box(self, "Impossible d'ouvrir : %s" % e, Gtk.MessageType.ERROR)

    def selected(self):
        model, paths = self.tree.get_selection().get_selected_rows()
        return [model[p][4] for p in paths]

    def new_folder(self):
        n = prompt(self, "Nom du nouveau dossier", "Nouveau dossier")
        if n:
            try:
                os.mkdir(os.path.join(self.cwd, n))
            except Exception as e:
                info_box(self, str(e), Gtk.MessageType.ERROR)
            self.load(self.cwd, push=False)

    def rename(self):
        sel = self.selected()
        if len(sel) != 1:
            return
        n = prompt(self, "Nouveau nom", os.path.basename(sel[0]))
        if n:
            try:
                os.rename(sel[0], os.path.join(os.path.dirname(sel[0]), n))
            except Exception as e:
                info_box(self, str(e), Gtk.MessageType.ERROR)
            self.load(self.cwd, push=False)

    def trash(self):
        sel = self.selected()
        if sel and ask(self, "Mettre %d élément(s) à la corbeille ?" % len(sel)):
            for p in sel:
                try:
                    Gio.File.new_for_path(p).trash(None)
                except Exception as e:
                    info_box(self, str(e), Gtk.MessageType.ERROR)
            self.load(self.cwd, push=False)

    def on_click(self, tree, ev):
        if ev.button != 3:
            return False
        res = tree.get_path_at_pos(int(ev.x), int(ev.y))
        if res and not tree.get_selection().path_is_selected(res[0]):
            tree.get_selection().unselect_all()
            tree.get_selection().select_path(res[0])
        m = Gtk.Menu()
        def item(label, cb):
            i = Gtk.MenuItem(label=label)
            i.connect("activate", lambda _: cb())
            m.append(i)
        if res:
            item("Ouvrir", lambda: self.open_row(res[0]))
            item("Renommer", self.rename)
            item("Mettre à la corbeille", self.trash)
            item("Copier le chemin", lambda: Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(self.selected()[0], -1))
        item("Nouveau dossier", self.new_folder)
        item("Ouvrir un terminal ici", lambda: run_detached(["gnome-terminal", "--working-directory=" + self.cwd]))
        m.show_all()
        m.popup_at_pointer(ev)
        return True


# ----------------------------------------------------------------------------
class MonitorApp(Gtk.Window):
    def __init__(self):
        super().__init__(title="Moniteur système QUENTIN OS")
        self.set_default_size(820, 600)
        self.last_cpu = None
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=14)
        self.add(v)
        self.bars = {}
        for name in ("Processeur", "Mémoire", "Disque"):
            r = Gtk.Box(spacing=10)
            l = Gtk.Label(label=name, xalign=0)
            l.set_size_request(110, -1)
            bar = Gtk.LevelBar(min_value=0, max_value=100, hexpand=True)
            val = Gtk.Label(xalign=1)
            val.set_size_request(190, -1)
            r.pack_start(l, False, False, 0)
            r.pack_start(bar, True, True, 0)
            r.pack_start(val, False, False, 0)
            v.pack_start(r, False, False, 0)
            self.bars[name] = (bar, val)
        self.store = Gtk.ListStore(int, str, str, str, str)
        self.tree = Gtk.TreeView(model=self.store)
        for i, t in enumerate(("PID", "Utilisateur", "CPU %", "Mémoire %", "Processus")):
            col = Gtk.TreeViewColumn(t, Gtk.CellRendererText(), text=i)
            col.set_sort_column_id(i)
            col.set_resizable(True)
            self.tree.append_column(col)
        sc = Gtk.ScrolledWindow()
        sc.add(self.tree)
        v.pack_start(sc, True, True, 0)
        bb = Gtk.Box(spacing=8)
        for label, sig in (("Terminer le processus", signal.SIGTERM), ("Forcer l'arrêt", signal.SIGKILL)):
            b = Gtk.Button(label=label)
            b.connect("clicked", lambda _, s=sig: self.kill(s))
            bb.pack_start(b, False, False, 0)
        v.pack_start(bb, False, False, 0)
        self.tick()
        GLib.timeout_add_seconds(2, self.tick)

    def kill(self, sig):
        model, it = self.tree.get_selection().get_selected()
        if not it:
            return
        pid = model[it][0]
        if ask(self, "Envoyer le signal à %s (PID %d) ?" % (model[it][4], pid)):
            try:
                os.kill(pid, sig)
            except Exception as e:
                info_box(self, "Impossible : %s" % e, Gtk.MessageType.ERROR)

    def tick(self):
        try:
            f = open("/proc/stat").readline().split()[1:]
            f = [int(x) for x in f]
            idle, total = f[3] + f[4], sum(f)
            if self.last_cpu:
                dt, di = total - self.last_cpu[1], idle - self.last_cpu[0]
                pct = 100.0 * (dt - di) / dt if dt else 0
                self.bars["Processeur"][0].set_value(pct)
                self.bars["Processeur"][1].set_text("%d %%" % pct)
            self.last_cpu = (idle, total)
            mi = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo")}
            used = mi["MemTotal"] - mi["MemAvailable"]
            self.bars["Mémoire"][0].set_value(100.0 * used / mi["MemTotal"])
            self.bars["Mémoire"][1].set_text("%s / %s" % (GLib.format_size(used * 1024), GLib.format_size(mi["MemTotal"] * 1024)))
            u = shutil.disk_usage("/")
            self.bars["Disque"][0].set_value(100.0 * u.used / u.total)
            self.bars["Disque"][1].set_text("%s / %s" % (GLib.format_size(u.used), GLib.format_size(u.total)))
            sel = self.tree.get_selection().get_selected()
            keep = sel[0][sel[1]][0] if sel[1] else None
            out = subprocess.run(["ps", "-eo", "pid,user:16,pcpu,pmem,comm", "--sort=-pcpu", "--no-headers"], capture_output=True, text=True).stdout
            self.store.clear()
            for line in out.splitlines()[:250]:
                p = line.split(None, 4)
                if len(p) == 5:
                    it = self.store.append([int(p[0]), p[1], p[2], p[3], p[4]])
                    if keep == int(p[0]):
                        self.tree.get_selection().select_iter(it)
        except Exception:
            pass
        return True


# ----------------------------------------------------------------------------
class NotesApp(Gtk.Window):
    DIR = os.path.join(HOME, "Documents", "Notes-QUENTIN-OS")

    def __init__(self):
        super().__init__(title="Notes QUENTIN OS")
        self.set_default_size(900, 580)
        os.makedirs(self.DIR, exist_ok=True)
        self.cur = None
        self.timer = None
        self.loading = False
        paned = Gtk.Paned()
        self.add(paned)
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, margin=8)
        left.set_size_request(250, -1)
        self.search = Gtk.SearchEntry()
        self.search.connect("search-changed", lambda _: self.reload())
        left.pack_start(self.search, False, False, 0)
        self.store = Gtk.ListStore(str, str)
        self.list = Gtk.TreeView(model=self.store, headers_visible=False)
        self.list.append_column(Gtk.TreeViewColumn("Note", Gtk.CellRendererText(ellipsize=3), text=0))
        self.list.get_selection().connect("changed", self.on_select)
        sc = Gtk.ScrolledWindow()
        sc.add(self.list)
        left.pack_start(sc, True, True, 0)
        bb = Gtk.Box(spacing=6)
        nb = Gtk.Button(label="Nouvelle note")
        nb.connect("clicked", lambda _: self.new_note())
        db = Gtk.Button(label="Supprimer")
        db.connect("clicked", lambda _: self.delete())
        bb.pack_start(nb, True, True, 0)
        bb.pack_start(db, True, True, 0)
        left.pack_start(bb, False, False, 0)
        paned.pack1(left, False, False)
        self.view = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD, left_margin=16, right_margin=16, top_margin=14, sensitive=False)
        self.buf = self.view.get_buffer()
        self.buf.connect("changed", self.on_change)
        sc2 = Gtk.ScrolledWindow()
        sc2.add(self.view)
        paned.pack2(sc2, True, False)
        self.connect("delete-event", lambda *a: (self.flush(), False)[1])
        self.reload()

    def reload(self, select=None):
        q = self.search.get_text().lower()
        items = []
        for n in os.listdir(self.DIR):
            if n.endswith(".txt"):
                p = os.path.join(self.DIR, n)
                try:
                    txt = open(p, encoding="utf-8").read()
                except Exception:
                    continue
                if q and q not in txt.lower():
                    continue
                items.append((os.path.getmtime(p), (txt.strip().splitlines() or ["(note vide)"])[0][:60], p))
        items.sort(reverse=True)
        self.store.clear()
        for _, t, p in items:
            it = self.store.append([t, p])
            if p == (select or self.cur):
                self.list.get_selection().select_iter(it)

    def on_select(self, sel):
        model, it = sel.get_selected()
        if not it:
            return
        self.flush()
        self.cur = model[it][1]
        self.loading = True
        try:
            self.buf.set_text(open(self.cur, encoding="utf-8").read())
        except Exception:
            self.buf.set_text("")
        self.loading = False
        self.view.set_sensitive(True)

    def on_change(self, buf):
        if self.loading or not self.cur:
            return
        if self.timer:
            GLib.source_remove(self.timer)
        self.timer = GLib.timeout_add(700, self.flush)

    def flush(self):
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = None
        if self.cur:
            try:
                open(self.cur, "w", encoding="utf-8").write(self.buf.get_text(self.buf.get_start_iter(), self.buf.get_end_iter(), True))
            except Exception as e:
                info_box(self, "Enregistrement impossible : %s" % e, Gtk.MessageType.ERROR)
        return False

    def new_note(self):
        self.flush()
        p = os.path.join(self.DIR, "note-%s.txt" % time.strftime("%Y%m%d-%H%M%S"))
        open(p, "w").close()
        self.cur = p
        self.reload(select=p)
        self.view.set_sensitive(True)
        self.view.grab_focus()

    def delete(self):
        if self.cur and ask(self, "Supprimer cette note ?"):
            try:
                os.remove(self.cur)
            except Exception:
                pass
            self.cur = None
            self.loading = True
            self.buf.set_text("")
            self.loading = False
            self.view.set_sensitive(False)
            self.reload()


# ----------------------------------------------------------------------------
OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Div: operator.truediv, ast.Pow: operator.pow, ast.Mod: operator.mod}


def safe_eval(expr):
    def ev(n):
        if isinstance(n, ast.Expression):
            return ev(n.body)
        if isinstance(n, ast.Constant) and isinstance(n.value, (int, float)):
            return n.value
        if isinstance(n, ast.BinOp) and type(n.op) in OPS:
            a, b = ev(n.left), ev(n.right)
            if isinstance(n.op, ast.Pow) and abs(b) > 1000:
                raise ValueError("exposant trop grand")
            return OPS[type(n.op)](a, b)
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, (ast.USub, ast.UAdd)):
            return -ev(n.operand) if isinstance(n.op, ast.USub) else ev(n.operand)
        raise ValueError("expression invalide")
    expr = expr.replace("÷", "/").replace("×", "*").replace("−", "-").replace("^", "**").replace(",", ".").replace("%", "%")
    return ev(ast.parse(expr, mode="eval"))


class CalcApp(Gtk.Window):
    def __init__(self):
        super().__init__(title="Calculatrice QUENTIN OS")
        self.set_resizable(False)
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=14)
        self.add(v)
        self.hist = Gtk.Label(xalign=1)
        v.pack_start(self.hist, False, False, 0)
        self.entry = Gtk.Entry(xalign=1, width_chars=18)
        self.entry.override_font(__import__("gi.repository.Pango", fromlist=["x"]).FontDescription("Inter 26"))
        self.entry.connect("activate", lambda _: self.equals())
        v.pack_start(self.entry, False, False, 0)
        g = Gtk.Grid(row_spacing=6, column_spacing=6, row_homogeneous=True, column_homogeneous=True)
        keys = [["C", "(", ")", "÷"], ["7", "8", "9", "×"], ["4", "5", "6", "−"], ["1", "2", "3", "+"], ["0", ".", "⌫", "="]]
        for r, rowk in enumerate(keys):
            for c, k in enumerate(rowk):
                b = Gtk.Button(label=k)
                b.set_size_request(70, 58)
                b.connect("clicked", self.press, k)
                g.attach(b, c, r, 1, 1)
        v.pack_start(g, False, False, 0)

    def press(self, _, k):
        if k == "C":
            self.entry.set_text("")
            self.hist.set_text("")
        elif k == "⌫":
            self.entry.set_text(self.entry.get_text()[:-1])
        elif k == "=":
            self.equals()
        else:
            self.entry.set_text(self.entry.get_text() + k)
        self.entry.set_position(-1)

    def equals(self):
        e = self.entry.get_text()
        if not e.strip():
            return
        try:
            r = safe_eval(e)
            txt = "%d" % r if float(r).is_integer() and abs(r) < 1e15 else "%.12g" % r
            self.hist.set_text(e + " =")
            self.entry.set_text(txt)
        except ZeroDivisionError:
            self.hist.set_text(e)
            self.entry.set_text("Division par zéro")
        except Exception:
            self.hist.set_text(e)
            self.entry.set_text("Erreur")


APPS = {"settings": SettingsApp, "files": FilesApp, "monitor": MonitorApp, "notes": NotesApp, "calc": CalcApp}

if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "settings"
    if name not in APPS:
        sys.exit("Usage : quentin_apps.py settings|files|monitor|notes|calc")
    GLib.set_prgname("quentin-" + name)
    win = APPS[name](sys.argv[2]) if (name == "files" and len(sys.argv) > 2) else APPS[name]()
    win.set_icon_name("quentin-" + name)
    try:
        win.set_wmclass("quentin-" + name, "quentin-" + name)
    except Exception:
        pass
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()

QAPPSEOF
cat > "$DATA/gen_icons.py" <<'QICONEOF'
#!/usr/bin/env python3
"""Génère le thème d'icônes QUENTIN OS (tuiles en verre, traits cyan/violet)."""
import os, sys

OUT = sys.argv[1]
APPS = os.path.join(OUT, "scalable", "apps")
os.makedirs(APPS, exist_ok=True)

DEFS = ('<defs>'
        '<linearGradient id="t" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#171a58"/><stop offset="1" stop-color="#3a0f6b"/></linearGradient>'
        '<linearGradient id="a" gradientUnits="userSpaceOnUse" x1="40" y1="40" x2="216" y2="216"><stop offset="0" stop-color="#22d3ee"/><stop offset="1" stop-color="#c084fc"/></linearGradient>'
        '</defs>')
TILE = ('<rect x="12" y="12" width="232" height="232" rx="58" fill="url(#t)" stroke="url(#a)" stroke-width="7"/>'
        '<path d="M12 76 a58 58 0 0 1 58-58 h116 a58 58 0 0 1 58 58 v14 q-116 44 -232 0z" fill="#ffffff" opacity="0.07"/>')
G = '<g fill="none" stroke="url(#a)" stroke-width="13" stroke-linecap="round" stroke-linejoin="round">%s</g>'
FILL = 'fill="url(#a)" stroke="none"'

GLYPHS = {
 "folder": '<path d="M56 100 v-14 a10 10 0 0 1 10-10 h36 l16 18 h72 a10 10 0 0 1 10 10 v68 a10 10 0 0 1 -10 10 h-124 a10 10 0 0 1 -10-10z"/>',
 "terminal": '<path d="M70 92 l46 36 -46 36"/><path d="M132 172 h58"/>',
 "globe": '<circle cx="128" cy="128" r="62"/><ellipse cx="128" cy="128" rx="26" ry="62"/><path d="M66 128 h124"/><path d="M78 98 q50 18 100 0"/><path d="M78 158 q50 -18 100 0"/>',
 "gear": '<circle cx="128" cy="128" r="46"/><circle cx="128" cy="128" r="20"/><circle cx="128" cy="128" r="64" stroke-width="20" stroke-dasharray="15 18.4"/>',
 "calc": '<rect x="84" y="62" width="88" height="132" rx="14"/><path d="M100 88 h56" stroke-width="10"/>'
         '<circle cx="104" cy="124" r="3" ' + FILL + '/><circle cx="128" cy="124" r="3" ' + FILL + '/><circle cx="152" cy="124" r="3" ' + FILL + '/>'
         '<circle cx="104" cy="150" r="3" ' + FILL + '/><circle cx="128" cy="150" r="3" ' + FILL + '/><circle cx="152" cy="150" r="3" ' + FILL + '/>'
         '<circle cx="104" cy="176" r="3" ' + FILL + '/><circle cx="128" cy="176" r="3" ' + FILL + '/><circle cx="152" cy="176" r="3" ' + FILL + '/>',
 "monitor": '<path d="M58 170 l32-44 28 22 30-56 50 54"/><path d="M58 196 h140"/>',
 "notes": '<rect x="80" y="60" width="96" height="136" rx="14"/><path d="M100 98 h56"/><path d="M100 126 h56"/><path d="M100 154 h34"/>',
 "bag": '<rect x="72" y="98" width="112" height="94" rx="16"/><path d="M104 98 v-10 a24 24 0 0 1 48 0 v10"/><path d="M110 140 q18 18 36 0"/>',
 "play": '<path d="M102 80 l78 48 -78 48z"/>',
 "music": '<path d="M112 170 v-84 l62 -14 v82"/><circle cx="96" cy="172" r="16"/><circle cx="158" cy="158" r="16"/>',
 "image": '<rect x="62" y="82" width="132" height="98" rx="14"/><circle cx="100" cy="114" r="9"/><path d="M70 172 l38 -36 24 22 22 -18 34 32"/>',
 "record": '<circle cx="128" cy="128" r="58"/><circle cx="128" cy="128" r="22" ' + FILL + '/>',
 "film": '<rect x="64" y="76" width="128" height="104" rx="14"/><path d="M92 76 v104"/><path d="M164 76 v104"/><path d="M64 110 h28"/><path d="M64 146 h28"/><path d="M164 110 h28"/><path d="M164 146 h28"/>',
 "pen": '<path d="M70 190 l12 -42 82 -82 30 30 -82 82z"/><path d="M146 84 l30 30"/>',
 "wave": '<path d="M58 128 h24 l14 -46 26 92 22 -66 16 40 h38"/>',
 "download": '<path d="M128 70 v86"/><path d="M92 124 l36 36 36 -36"/><path d="M70 190 h116"/>',
 "mail": '<rect x="62" y="88" width="132" height="92" rx="14"/><path d="M66 98 l62 46 62 -46"/>',
 "qlogo": '<circle cx="124" cy="124" r="58"/><path d="M146 146 l40 40" stroke-width="16"/>',
 "generic": '<circle cx="128" cy="128" r="56"/><circle cx="128" cy="128" r="14" ' + FILL + '/>',
}

# nom d'icône système (ou de l'appli) -> glyphe
MAP = {
 "quentin-files": "folder", "quentin-settings": "gear", "quentin-monitor": "monitor", "quentin-notes": "notes", "quentin-calc": "calc",
 "firefox": "globe", "firefox-esr": "globe", "web-browser": "globe",
 "nemo": "folder", "system-file-manager": "folder", "org.gnome.Nautilus": "folder",
 "org.gnome.Terminal": "terminal", "utilities-terminal": "terminal", "gnome-terminal": "terminal",
 "mintinstall": "bag", "softwarecenter": "bag", "org.gnome.Software": "bag", "system-software-install": "bag",
 "preferences-system": "gear", "cinnamon-settings": "gear", "preferences-desktop": "gear", "cs-general": "gear",
 "vlc": "play", "io.github.celluloid_player.Celluloid": "play", "celluloid": "play", "totem": "play", "org.gnome.Totem": "play",
 "rhythmbox": "music", "org.gnome.Rhythmbox3": "music", "audio-x-generic": "music",
 "org.gnome.Calculator": "calc", "accessories-calculator": "calc", "gnome-calculator": "calc",
 "org.gnome.SystemMonitor": "monitor", "utilities-system-monitor": "monitor", "gnome-system-monitor": "monitor",
 "xed": "notes", "accessories-text-editor": "notes", "org.gnome.gedit": "notes",
 "gimp": "pen", "org.inkscape.Inkscape": "pen", "inkscape": "pen",
 "audacity": "wave", "com.obsproject.Studio": "record", "obs": "record",
 "org.kde.kdenlive": "film", "kdenlive": "film", "fr.handbrake.ghb": "film", "ghb": "film",
 "shotwell": "image", "org.gnome.Shotwell": "image", "pix": "image", "eog": "image", "org.gnome.eog": "image",
 "mintupdate": "download", "mintupdate-symbolic": "download", "warpinator": "download", "transmission-gtk": "download",
 "thunderbird": "mail", "org.mozilla.Thunderbird": "mail", "mail-client": "mail",
 "mint-logo": "qlogo", "start-here": "qlogo", "linuxmint-logo": "qlogo",
}

import re
def fixlines(g):
    # chemins "M x y h n" / "M x y v n" réécrits en lignes absolues (compatibilité maximale)
    g = re.sub(r'M(-?\d+) (-?\d+) h(-?\d+)', lambda m: 'M%s %s L%d %s' % (m.group(1), m.group(2), int(m.group(1)) + int(m.group(3)), m.group(2)), g)
    g = re.sub(r'M(-?\d+) (-?\d+) v(-?\d+)', lambda m: 'M%s %s L%s %d' % (m.group(1), m.group(2), m.group(1), int(m.group(2)) + int(m.group(3))), g)
    return g
GLYPHS = {k: fixlines(v) for k, v in GLYPHS.items()}

n = 0
for name, glyph in MAP.items():
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">%s%s%s</svg>'
           % (DEFS, TILE, G % GLYPHS[glyph]))
    open(os.path.join(APPS, name + ".svg"), "w").write(svg)
    n += 1

open(os.path.join(OUT, "index.theme"), "w").write(
"""[Icon Theme]
Name=Quentin-Icons
Comment=Icônes QUENTIN OS (tuiles en verre, cyan et violet)
Inherits=Papirus-Dark,Adwaita,hicolor
Directories=scalable/apps

[scalable/apps]
Size=256
MinSize=8
MaxSize=512
Type=Scalable
Context=Applications
""")
print("%d icônes générées dans %s" % (n, OUT))

QICONEOF
python3 "$DATA/gen_icons.py" "$HOME/.local/share/icons/Quentin-Icons"
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/Quentin-Icons" 2>/dev/null || true
chmod +x "$DATA/apps/quentin_apps.py"

mkapp() {  # id  nom  commentaire  mots-clés
  cat > "$HOME/.local/share/applications/quentin-$1.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Comment=$3
Exec=python3 $DATA/apps/quentin_apps.py $1
Icon=quentin-$1
Terminal=false
StartupWMClass=quentin-$1
Categories=Utility;
Keywords=$4
EOF
}
mkapp settings "Paramètres" "Réglages de QUENTIN OS" "paramètres;réglages;thème;fond;barre"
mkapp files "Fichiers" "Explorateur de fichiers QUENTIN OS" "fichiers;dossiers;explorateur"
mkapp monitor "Moniteur système" "CPU, mémoire, disque et processus" "moniteur;processus;cpu;ram;tâches"
mkapp notes "Notes" "Prise de notes QUENTIN OS" "notes;texte"
mkapp calc "Calculatrice" "Calculatrice QUENTIN OS" "calcul;calculatrice"

# Applications d'origine : renommées (même programme) ou masquées si QUENTIN OS a sa propre version
python3 - <<'PYEOF2'
import os
src = "/usr/share/applications"
dst = os.path.expanduser("~/.local/share/applications")
rename = {"nemo.desktop": "Fichiers avancés", "mintinstall.desktop": "Logiciels", "cinnamon-settings.desktop": "Paramètres système",
          "mintupdate.desktop": "Mises à jour", "xed.desktop": "Éditeur de texte"}
hide = ["org.gnome.Calculator.desktop", "gnome-calculator.desktop", "org.gnome.SystemMonitor.desktop", "gnome-system-monitor.desktop"]
for fn in list(rename) + hide:
    sp = os.path.join(src, fn)
    if not os.path.exists(sp):
        continue
    out = ["# QUENTIN-OS-OVERRIDE"]
    for line in open(sp, encoding="utf-8"):
        l = line.rstrip("\n")
        if l.startswith("Name[") or l.startswith("GenericName[") or l.startswith("Comment["):
            continue
        if l.startswith("Name=") and fn in rename:
            l = "Name=" + rename[fn]
        out.append(l)
    if fn in hide:
        out.append("NoDisplay=true")
    open(os.path.join(dst, fn), "w", encoding="utf-8").write("\n".join(out) + "\n")
print("Applications d'origine adaptées.")
PYEOF2
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

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
.grouped-window-list-item-box { border-radius: 16px; margin: 6px 4px; padding: 0 10px; background-color: rgba(34,211,238,0.07); border: 1px solid rgba(34,211,238,0.55); border-bottom: 3px solid rgba(34,211,238,0.55); transition-duration: 150; }
.grouped-window-list-item-box:hover { background-color: rgba(34,211,238,0.22); box-shadow: 0 0 16px rgba(34,211,238,0.6); }
.grouped-window-list-item-box:focus, .grouped-window-list-item-box:active { background-color: rgba(168,85,247,0.34); border: 1px solid #22d3ee; border-bottom: 3px solid #22d3ee; box-shadow: 0 0 16px rgba(168,85,247,0.7); }
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
gs org.cinnamon.desktop.interface icon-theme "Quentin-Icons"
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
gs org.cinnamon favorite-apps "['quentin-files.desktop', 'firefox.desktop', 'org.gnome.Terminal.desktop', 'quentin-settings.desktop', 'mintinstall.desktop', 'vlc.desktop', 'org.gnome.Rhythmbox3.desktop', 'quentin-notes.desktop', 'quentin-calc.desktop', 'quentin-monitor.desktop']"
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

if [ "$PLY" -eq 1 ]; then
log "   Menu de démarrage (GRUB) : fond et couleurs QUENTIN OS"
sudo mkdir -p /etc/default/grub.d
sudo tee /etc/default/grub.d/99-quentin.cfg >/dev/null <<EOF
GRUB_DISTRIBUTOR="QUENTIN OS"
GRUB_THEME=""
GRUB_BACKGROUND="$SYS_BG/wallpaper-fhd.png"
GRUB_COLOR_NORMAL="light-cyan/black"
GRUB_COLOR_HIGHLIGHT="white/magenta"
GRUB_GFXMODE=auto
EOF
sudo update-grub || log "  (update-grub a échoué : le menu GRUB reste inchangé)"
fi

# ----------------------------------------------------------------------------
log "7b/8 Nom du système : QUENTIN OS (GRUB, écran de connexion, À propos)"
mkdir -p "$BACKUP/rename"
for f in $RENAME_FILES; do
  [ -f "$f" ] || continue
  d="$BACKUP/rename/$(echo "$f" | tr / _)"
  [ -f "$d" ] || cp "$f" "$d"
done
sudo sed -i --follow-symlinks -E 's/^(NAME|PRETTY_NAME)=.*/\1="QUENTIN OS"/' /etc/os-release 2>/dev/null || true
[ -f /etc/lsb-release ] && sudo sed -i --follow-symlinks -E 's/^DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION="QUENTIN OS"/' /etc/lsb-release || true
[ -f /etc/linuxmint/info ] && sudo sed -i -E 's/^DESCRIPTION=.*/DESCRIPTION="QUENTIN OS"/' /etc/linuxmint/info || true
[ -f /usr/share/xsessions/cinnamon.desktop ] && sudo sed -i -E '/^Name\[/d; s/^Name=.*/Name=QUENTIN OS/' /usr/share/xsessions/cinnamon.desktop || true
[ -f /usr/share/xsessions/cinnamon2d.desktop ] && sudo sed -i -E '/^Name\[/d; s/^Name=.*/Name=QUENTIN OS (rendu logiciel)/' /usr/share/xsessions/cinnamon2d.desktop || true
sudo mkdir -p /etc/default/grub.d
echo 'GRUB_DISTRIBUTOR="QUENTIN OS"' | sudo tee /etc/default/grub.d/98-quentin-name.cfg >/dev/null
sudo update-grub >/dev/null 2>&1 || log "  (update-grub a échoué : le nom dans GRUB changera au prochain essai)"

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
patch("menu@cinnamon.org", {"menu-icon-custom": True, "menu-icon": os.path.expanduser("~/.local/share/icons/Quentin-Icons/scalable/apps/start-here.svg"), "menu-label": ""})
patch("grouped-window-list@cinnamon.org", {"pinned-apps": ["quentin-files.desktop", "firefox.desktop", "org.gnome.Terminal.desktop", "quentin-settings.desktop", "mintinstall.desktop", "vlc.desktop", "org.gnome.Rhythmbox3.desktop", "quentin-notes.desktop"]})
PYEOF
nohup cinnamon --replace >/dev/null 2>&1 &
disown || true

log "Terminé. QUENTIN OS est appliqué."
log "Déconnectez-vous puis reconnectez-vous pour tout voir (écran de connexion inclus)."
log "Widgets : glissez-les à la souris ; clic droit > Retirer pour les supprimer (clic droit sur le bureau > Ajouter des desklets pour les remettre)."
log "Pour revenir en arrière : bash $(basename "$0") uninstall"
