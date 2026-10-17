# ⛏ MineOS Gaming Edition

OS basé sur Debian 12 Live — optimisé gaming, GPU universel.

## 🚀 Compiler via GitHub Actions

1. Fork ce repo sur ton compte GitHub
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
| Base | Debian 12 Bookworm Live |
| Navigateur | Google Chrome |
| Gaming | Steam, Lutris, PlayOnLinux |
| Compatibilité .exe | Wine + DXVK (DirectX→Vulkan) |
| Boost gaming | GameMode (CPU perf auto) |
| Overlay FPS | MangoHud (Shift+F12) |
| Kernel | Liquorix (low-latency) |
| GPU NVIDIA | nvidia-driver + TripleBuffer |
| GPU AMD | AMDGPU + RADV Vulkan + ACO |
| GPU Intel | i915 GuC/HuC + Iris Vulkan |
| Bureau | Openbox + thème MineOS Dark |
| Apps | Thunar, Tilix, VLC, GIMP, Mousepad |

## ⌨️ Raccourcis

| Touche | Action |
|--------|--------|
| Super+Entrée | Terminal |
| Super+B | Chrome |
| Super+G | Steam |
| Super+L | Lutris |
| Super+E | Fichiers |
| Super+R | Lanceur d'apps |
| Shift+F12 | Toggle MangoHud (overlay FPS) |
| Clic droit bureau | Menu |

## 💻 Commandes terminal

```bash
exe fichier.exe        # Wine + GameMode
exe-dxvk fichier.exe   # Wine + DXVK + overlay FPS
steam                  # Steam avec GameMode
gpu                    # Infos GPU / Vulkan / VRAM
dxvk                   # Activer DXVK dans le prefix Wine
```

## 📊 RAM estimée (i3-7020U + 16 GB)

| Situation | RAM utilisée |
|-----------|-------------|
| Idle bureau | ~380 MB |
| + Chrome 5 onglets | ~900 MB |
| + Steam ouvert | ~1,2 GB |
| + Jeu Wine | ~2,5 GB |
