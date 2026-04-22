# Turtle Miner v1.1

Programa de minería eficiente para turtles de **CC:Tweaked** con soporte para periféricos de **Advanced Peripherals** (Environment Detector y Geo Scanner).

Diseñado para **turtles no-advanced** (pantalla 39x13, sin color). Todo el renderizado usa solo caracteres ASCII.

## Qué hace

- **Branch mining** con ancho configurable (1x3 rápido o 3x3 completo): túnel principal con ramas laterales cada X bloques. El 3x3 cava todas las columnas correctamente (centro + laterales).
- **Resume tras apagado**: el estado se guarda en `miner/state.dat` cada paso. Si el chunk se descarga o la turtle se apaga, al reiniciar ofrece reanudar desde el último paso completado.
- **Auto-refuel inteligente**: cuando el fuel baja del umbral, busca carbón (`minecraft:coal`) o carbón vegetal (`minecraft:charcoal`) en el inventario y lo quema, dejando una reserva.
- **Colocación de cofres sin bloquear paso**: cuando el inventario está casi lleno, gira a la derecha, cava un hueco en la pared lateral, coloca el cofre dentro (así no obstruye el túnel) y vacía todo menos fuel y cofres.
- **Detección de minerales** con `turtle.inspect()` en las tres direcciones. Lleva log de lo encontrado.
- **UI con dashboard completo**: splash ASCII al inicio, menú interactivo para configurar patrón/longitud/ramas, y dashboard en vivo durante la ejecución con barras de progreso, fuel, slots, posición XYZ, tiempo y peripherals detectados.
- **Environment Detector (Advanced Peripherals)**: detecta bioma peligroso y escanea mobs hostiles si los tienes.
- **Geo Scanner (opcional)**: si lo conectas en el futuro, el programa lo detecta automáticamente y muestra el mineral más cercano mientras mina. Respeta cooldown y límite de FE.
- **Return-to-start** al terminar o cuando detecta fuel crítico: vuelve al inicio y deja un cofre final con el loot.

## Estructura

```
turtle-miner/
├── startup.lua              ← entry point (se ejecuta al encender)
├── miner/
│   ├── ui.lua               ← splash, menús, dashboard
│   ├── config.lua           ← menú inicial de configuración
│   ├── persist.lua          ← save/load de state para resume
│   ├── peripherals.lua      ← detección de Env Detector + Geo Scanner
│   ├── inventory.lua        ← refuel, filtrado, cofres
│   ├── movement.lua         ← movimiento seguro + tracking XYZ
│   └── mining.lua           ← branch/tunnel mining, return-to-start
└── README.md
```

## Instalación

Copia toda la carpeta `turtle-miner/` al disco de la turtle. La forma más rápida si tienes un disk drive:

1. Mete un disquete en el disk drive junto a la turtle
2. Copia los archivos al disquete
3. En la turtle: `cp disk/startup.lua startup.lua` y `cp -r disk/miner miner`

O si tienes HTTP habilitado, usa `wget` / `pastebin get` para cada archivo.

## Requisitos

- **Mining Turtle** (con pico de diamante o netherita en cualquiera de los dos slots de upgrade)
- **Coal o Charcoal** en algún slot del inventario (para auto-refuel)
- **Cofres** (recomendado 4-8) en algún slot del inventario (para volcar loot)
- Opcional: **Environment Detector** conectado o como upgrade
- Opcional: **Geo Scanner** conectado o como upgrade

## Cómo usar

1. Coloca la turtle mirando hacia donde quieres que empiece a minar.
2. Mete combustible (coal) y unos cuantos cofres en el inventario.
3. Ejecuta `startup` o reinicia la turtle.
4. Sigue el menú:
   - Elige patrón (branch o tunnel)
   - Longitud del túnel principal
   - Longitud de ramas (solo branch)
   - Separación entre ramas (solo branch)
5. Confirma con Enter y a minar.

## Posición inicial recomendada

- **Y=-59** para diamantes (versiones 1.18+)
- Turtle en el suelo, mirando en la dirección del túnel
- Espacio libre a la derecha para que pueda colocar cofres

## Notas técnicas

- Posición se trackea relativa al punto de inicio: (0,0,0) mirando +X.
- `facing` usa 0=+X, 1=+Z, 2=-X, 3=-Z.
- Si algo bloquea un movimiento (mob, grava), reintenta hasta 8 veces cavando/atacando.
- El patrón 3x3 usa una optimización: la turtle avanza una vez y luego gira a izquierda y derecha para cavar las paredes. Esto ahorra movimientos comparado con 3 pasadas paralelas.
- Geo Scanner: si existe pero no tiene FE suficiente o está en cooldown, el programa lo ignora sin romper nada.

## Fuentes consultadas

- [CC:Tweaked Turtle API](https://tweaked.cc/module/turtle.html)
- [Advanced Peripherals - Environment Detector](https://docs.advanced-peripherals.de/0.7/peripherals/environment_detector/)
- [Advanced Peripherals - Geo Scanner](https://docs.advanced-peripherals.de/0.7/peripherals/geo_scanner/)
- [Equbuxu/mine - patrón de branch mining](https://github.com/Equbuxu/mine)
- [Starkus/quarry - patrones de refuel y movimiento seguro](https://github.com/Starkus/quarry)
- [tyler919/cc-mining-turtle](https://github.com/tyler919/cc-mining-turtle)
