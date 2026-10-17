# ⛏ MineOS Gaming Edition

OS basé sur Ubuntu 22.04 LTS — optimisé gaming, GPU universel.

## 🚀 Compiler via GitHub Actions

1. Fais un **Fork** de ce dépôt sur ton compte GitHub
2. Onglet **Actions** → activer les workflows
3. **Build MineOS Gaming ISO** → **Run workflow**
4. Attendre ~30 min
5. Télécharger l'ISO dans **Artifacts**

## 💿 Flasher l'ISO

```bash
# Linux
sudo dd if=MineOS-Gaming-1.0.0-x86_64.iso of=/dev/sdX bs=4M status=progress && sync

# Windows : Rufus ou balenaEtcher
```

## 🎮 Ce qui est inclus

| Composant | Détail |
|-----------|--------|
| Base | Ubuntu 22.04 LTS (Jammy Jellyfish) |
| Navigateur | Opera GX |
| Gaming | Steam, Lutris, PlayOnLinux |
| Compatibilité .exe | Wine + DXVK (DirectX→Vulkan) |
| Boost gaming | GameMode (CPU perf auto) |
| Overlay FPS | MangoHud (Shift_R+F12) |
| Kernel | Liquorix (low-latency, fallback kernel Ubuntu générique) |
| GPU NVIDIA | nvidia-driver (auto-détecté) + TripleBuffer |
| GPU AMD | AMDGPU + RADV Vulkan + ACO |
| GPU Intel | i915 GuC/HuC + Iris Vulkan |
| Bureau | XFCE4 + thème MineOS Dark |
| Apps | Thunar, xfce4-terminal, VLC, GIMP, Mousepad |
| Store | MineOS Store (apps Linux & Windows via Zenity) |

## ⌨️ Raccourcis bureau

| Touche | Action |
|--------|--------|
| Clic droit bureau | Menu |
| Barre des tâches → ⛏ MineOS | Menu Whisker |

## 💻 Commandes terminal

```bash
exe fichier.exe          # Wine + GameMode
exe-dxvk fichier.exe    # Wine + DXVK + overlay FPS
steam                   # Steam avec GameMode
gpu                     # Infos GPU / Vulkan
store                   # MineOS Store
wallpaper               # Changer le fond d'écran
```

## 📊 RAM estimée (i3-7020U + 16 GB)

| Situation | RAM utilisée |
|-----------|-------------|
| Idle bureau | ~380 MB |
| + Opera GX 5 onglets | ~900 MB |
| + Steam ouvert | ~1,2 GB |
| + Jeu Wine | ~2,5 GB |

## 🐛 Bugs corrigés (v9 → v10)

- **README** : mentionnait Chrome alors que le script installe Opera GX → corrigé
- **build-all.sh** : `set -uo pipefail` sans `-e` était incohérent avec les sous-scripts qui utilisent `set -e` → clarifié
- **hook 0100-opera** : pas de vérification si le dépôt Opera est joignable avant `apt-get update` → ajout d'un fallback
- **hook 0200-wine** : `dpkg --add-architecture i386` appelé deux fois (ici et dans 0300-steam) → dédupliqué dans un hook séparé `0150-i386`
- **hook 0500-gpu** : `lspci` dans un chroot live-build ne retourne rien (pas de `/proc` complet) → détection GPU déplacée dans un script runtime exécuté au démarrage
- **hook 0800-initramfs** : `mkinitramfs` pouvait échouer silencieusement si `/lib/modules/` était vide → ajout d'une vérification explicite
- **0600-xfce-desktop** : alias `chrome='opera'` dans `.bashrc` mais Opera s'appelle `opera` ou `opera-stable` → alias corrigé + ajout `opera-gx`
- **build.yml** : pas de `permissions: contents: write` pour le job de release → ajout explicite
