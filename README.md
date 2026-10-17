# ⛏ MineOS Gaming Edition — v14

> **Distribution Linux gaming clé en main**, basée sur Ubuntu 22.04 LTS  
> Build par **chroot direct** — plus de `live-build`, plus de bug initrd depuis la v6

---

## 🚀 Pourquoi v13 est différente

Depuis la v6, toutes les versions buguaient au même endroit :
```
cp: cannot stat 'chroot/boot/initrd.img-*': No such file or directory
```

**Cause racine :** `live-build` laisse `update-initramfs` en mode "deferred" dans le chroot, donc `initrd.img` n'est jamais généré quand `lb_chroot_hacks` en a besoin.

**Solution v13 :** On abandonne complètement `live-build` et on construit comme le font **Linux Mint**, **Pop!_OS** et **Zorin OS** :

| Ancienne approche (v1→v12) | Nouvelle approche (v13) |
|---------------------------|------------------------|
| `lb config` + `lb build` | Chroot direct sur Ubuntu |
| live-build gère l'initrd  | `mkinitramfs` appelé directement |
| Bug initrd systématique   | initrd généré à l'étape 5, vérifié avant de continuer |
| Patch lb_chroot_hacks     | **Supprimé** — inutile |

---

## 🎮 Contenu de l'ISO

### Gaming
| Outil | Description |
|-------|-------------|
| **Steam** | Bibliothèque Steam + Proton |
| **Lutris** | Gestionnaire multi-sources (GOG, Epic, etc.) |
| **Heroic Games** | Client Epic Games Store + GOG |
| **Wine + DXVK** | DirectX 9/10/11/12 → Vulkan via DXVK 2.3.1 |
| **Bottles** | Interface graphique Wine (Flatpak) |
| **GameMode** | Optimise les performances CPU/GPU pendant les jeux |
| **MangoHud** | Overlay FPS / CPU / GPU / RAM (Shift+F12) |

### GPU (détection automatique au démarrage)
- **NVIDIA** → `ubuntu-drivers install` + config Xorg
- **AMD** → Mesa RADV + `RADV_PERFTEST=aco,ngg`
- **Intel** → Mesa Iris + optimisations i915

### Bureau
- **XFCE** + thème **MineOS Dark** (vert #4ade80 sur fond sombre)
- **Papirus Dark** icônes
- **Opera GX** (ou Chromium en fallback si inaccessible)
- **MineOS Store** : installer apps Linux + Windows en 2 clics

### Applications préinstallées
Discord, Spotify, OBS Studio, VSCode, Kdenlive, Blender, GIMP, VLC, LibreOffice (via Flatpak au 1er démarrage)

### Optimisations système
- `vm.swappiness=10` — moins de swap, plus de RAM pour les jeux
- PulseAudio low-latency (5ms, realtime-priority=9)
- Limits système étendues (nofile, memlock)
- Kernel Liquorix si disponible (sinon Ubuntu générique)

---

## 🔨 Build

### GitHub Actions (recommandé)
1. Fork ce repo
2. `Actions → Build MineOS Gaming ISO → Run workflow`
3. L'ISO est disponible dans les Artifacts (~2.5-4 GB)

### En local
```bash
sudo bash scripts/build.sh 1.0.0
# ISO dans : /opt/mineos-output/
```

**Prérequis :**
```bash
sudo apt-get install squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \
    shim-signed mtools syslinux isolinux wget imagemagick python3-pil
```

---

## 💾 Créer une clé USB bootable

```bash
# Linux
sudo dd if=MineOS-Gaming-1.0.0-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync

# Ou Balena Etcher (Windows/macOS/Linux)
```

## ▶️ Démarrage

| Option GRUB | Usage |
|-------------|-------|
| **MineOS Gaming (Live)** | Mode normal — auto-login XFCE |
| **Mode sans échec (nomodeset)** | Si problème GPU/écran noir |
| **Mode RAM (toram)** | Tout en mémoire, plus rapide après chargement |

---

## ⚡ Système de patch automatique (.MineOSUp)

MineOS v14 intègre un **Update Watcher** — comme Windows Update, mais en mieux.

**Comment ça marche :**
1. Dépose un fichier `.MineOSUp` dans `/opt/mineos-updates/`
2. Le daemon le détecte instantanément
3. Il l'exécute automatiquement
4. Il le supprime après application
5. Redémarre si le patch le demande (`exit 42`)

**Créer un patch :**
```bash
cp updater/patches/MineOS-Update-NewBar.MineOSUp mon-patch.MineOSUp
# Modifie le contenu, puis dépose dans /opt/mineos-updates/
```

**Suivre les logs :**
```bash
tail -f /var/log/mineos-watcher.log
journalctl -u mineos-update-watcher -f
```

---

## 🗂️ Structure du projet

```
mineos-v14/
├── .github/workflows/
│   └── build.yml              # CI/CD GitHub Actions
├── scripts/
│   ├── build.sh               # Script principal (étapes 1-10)
│   ├── configure-chroot.sh    # Config MineOS dans le chroot
│   └── build-iso.sh           # Génération ISO avec xorriso
├── installer/
│   ├── install-core.sh        # Installeur système
│   ├── mineos-install.sh      # Script d'entrée installeur
│   └── mineos-installer.html  # Interface web installeur
└── updater/
    ├── MineOS-Update.sh        # Gestionnaire de mises à jour interactif
    ├── MineOS-Update.desktop   # Raccourci bureau
    ├── watcher/
    │   ├── mineos-watcher.sh              # Daemon de surveillance .MineOSUp
    │   ├── mineos-update-watcher.service  # Service systemd
    │   └── install-watcher.sh            # Installation manuelle du watcher
    └── patches/
        └── MineOS-Update-NewBar.MineOSUp  # Patch exemple — nouvelle barre
```

---

## ❓ FAQ

**Q: Pourquoi ne pas utiliser live-build ?**  
R: 7 versions de patches ont essayé de contourner le bug initrd de live-build sur Ubuntu dans GitHub Actions. La solution est d'arrêter d'utiliser live-build, pas de le patcher davantage.

**Q: L'ISO est-elle installable sur disque dur ?**  
R: Le live system Ubuntu inclut `ubiquity` ou `calamares` si tu veux ajouter un installeur. Pour l'instant, MineOS est un système live (démarrage depuis USB).

**Q: Le driver NVIDIA ne s'installe pas ?**  
R: Il se télécharge au 1er démarrage (le dépôt Ubuntu est contacté). Boot en mode sans échec (`nomodeset`) si l'écran est noir, puis attendre le service `mineos-gpu-detect`.
