# Turtle Multiprogram v1.2

Tres programas para turtles de **CC:Tweaked** compartiendo la misma base (persistencia, movimiento seguro, control remoto por rednet y swarm opcional con GPS):

- **Mining** — branch / tunnel mining con auto-fuel y cofres inteligentes.
- **Lumber** — tala automatizada de árboles (grid o single con bonemeal).
- **Farmer** — cultivo automático de trigo, zanahoria, patata y remolacha.

Diseñado para **turtles no-advanced** (pantalla 39x13, sin color). Todo el renderizado usa solo caracteres ASCII.

Al arrancar, la turtle muestra un menú para elegir programa. La selección y el progreso se persisten, así que tras un chunk-unload puedes reanudar exactamente donde estabas.

## Qué hace (mining)

- **Branch mining** con ancho configurable (1x3 rápido o 3x3 completo): túnel principal con ramas laterales cada X bloques. El 3x3 cava todas las columnas correctamente (centro + laterales).
- **Resume tras apagado**: el estado se guarda en `miner/state.dat` cada paso. Si el chunk se descarga o la turtle se apaga, al reiniciar ofrece reanudar desde el último paso completado.
- **Control remoto por rednet**: si la turtle tiene un wireless modem, se puede controlar desde otra computer con `client`: dashboard en vivo con posición, fuel y progreso, más comandos pause/resume/home/stop.
- **Auto-refuel inteligente**: cuando el fuel baja del umbral, busca carbón (`minecraft:coal`) o carbón vegetal (`minecraft:charcoal`) en el inventario y lo quema, dejando una reserva.
- **Colocación de cofres sin bloquear paso**: cuando el inventario está casi lleno, gira a la derecha, cava un hueco en la pared lateral, coloca el cofre dentro (así no obstruye el túnel) y vacía todo menos fuel y cofres.
- **Detección de minerales** con `turtle.inspect()` en las tres direcciones. Lleva log de lo encontrado.
- **UI con dashboard completo**: splash ASCII al inicio, menú interactivo para configurar patrón/longitud/ramas, y dashboard en vivo durante la ejecución con barras de progreso, fuel, slots, posición XYZ, tiempo y peripherals detectados.
- **Environment Detector (Advanced Peripherals)**: detecta bioma peligroso y escanea mobs hostiles si los tienes.
- **Geo Scanner (opcional)**: si lo conectas en el futuro, el programa lo detecta automáticamente y muestra el mineral más cercano mientras mina. Respeta cooldown y límite de FE.
- **Return-to-start** al terminar o cuando detecta fuel crítico: vuelve al inicio y deja un cofre final con el loot.

## Qué hace (lumber)

Automatiza una línea de árboles y repone saplings tras talar.

- **Modo grid**: N árboles en línea recta con un espaciado configurable (por defecto 2 bloques entre ellos). La turtle recorre la fila, inspecciona cada posición, y si hay un tronco maduro lo tala subiendo por la columna del tronco. Tras talar, replanta un sapling y opcionalmente aplica bonemeal. Al terminar la pasada vuelve a casa y vuelca logs en el cofre detrás.
- **Modo single**: un único árbol delante de la turtle; pensado para bonemeal (plantar → bonemeal 3x → talar → repetir).
- **Sleep configurable** entre ciclos (30s–1h).
- **Sapling slot**: la turtle busca automáticamente cualquier sapling en su inventario. Spruce es el ideal porque crece en columna 1×1 siempre.
- Funciona mejor con spruce; oak/birch a veces ramifican y el tronco se queda con leaves que la turtle ignora.

## Qué hace (farmer)

Automatiza un plot N×M de cultivos sobre farmland pre-preparado.

- **Cultivos soportados**: wheat, carrots, potatoes, beetroots.
- **Serpentina** sobre el plot a Y=2 (la turtle vuela 2 bloques por encima del farmland). Cada celda: `inspectDown` → si el cultivo está maduro (`age >= maxAge`), `digDown` y `placeDown` con la semilla del mismo cultivo.
- **Sleep configurable** entre ciclos (30s–1h); típico 10 minutos para esperar a que vuelva a crecer.
- Al terminar cada pasada vuelve a casa y vuelca todo menos semillas, saplings, fuel, cofres y bonemeal.
- Necesitas **1 bloque de agua por cada 9×9 de farmland** para mantenerlo regado.

## Estructura

```
turtle-miner/
├── startup.lua              ← entry point: elige programa y dispatcha
├── miner/
│   ├── ui.lua               ← splash, menús, dashboard
│   ├── config.lua           ← menús (mining / lumber / farmer)
│   ├── persist.lua          ← save/load de state para resume
│   ├── peripherals.lua      ← detección de Env Detector + Geo Scanner
│   ├── inventory.lua        ← refuel, filtrado, cofres, dumpInto
│   ├── movement.lua         ← movimiento seguro + tracking XYZ
│   ├── remote.lua           ← rednet listener + broadcast de status
│   ├── swarm.lua            ← GPS + ore map compartido
│   ├── mining.lua           ← branch/tunnel mining, return-to-start
│   ├── lumber.lua           ← tala grid/single + replant
│   └── farmer.lua           ← serpentina NxM + harvest+replant
└── README.md
```

## Instalación

Copia toda la carpeta `turtle-miner/` al disco de la turtle. La forma más rápida si tienes un disk drive:

1. Mete un disquete en el disk drive junto a la turtle
2. Copia los archivos al disquete
3. En la turtle: `cp disk/startup.lua startup.lua` y `cp -r disk/miner miner`

O si tienes HTTP habilitado, usa `wget` / `pastebin get` para cada archivo.

## Requisitos

**Para todos los programas:**
- **Turtle con pico** (mining turtle; diamante o netherita en slot de upgrade)
- **Coal o Charcoal** en algún slot del inventario (para auto-refuel)
- Opcional: **Wireless modem** en el slot de upgrade para control remoto por rednet

**Mining:**
- **Cofres** (recomendado 4-8) en el inventario para volcar loot
- Opcional: **Environment Detector** / **Geo Scanner** (Advanced Peripherals)

**Lumber:**
- **Saplings** en un slot (spruce recomendado, tronco 1×1)
- Opcional: **Bonemeal** para acelerar crecimiento
- **Un cofre colocado detrás de la turtle** (posición -1,0,0) para volcar logs

**Farmer:**
- **Semillas** de los cultivos que vayas a cultivar
  - Wheat: `minecraft:wheat_seeds`
  - Carrots: usa una `minecraft:carrot` como semilla
  - Potatoes: usa una `minecraft:potato` como semilla
  - Beetroots: `minecraft:beetroot_seeds`
- **Un cofre colocado detrás de la turtle** para volcar cosecha
- Plot de farmland ya preparado con agua cerca

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

## Posición inicial recomendada (mining)

- **Y=-59** para diamantes (versiones 1.18+)
- Turtle en el suelo, mirando en la dirección del túnel
- Espacio libre a la derecha para que pueda colocar cofres

## Layout (lumber grid)

La turtle mira +X. Los árboles crecen delante de ella en las posiciones impares:

```
[CHEST] [TURTLE] [air] [T1] [air] [T2] [air] [T3] ...
  -1       0       1     2    3     4    5     6
```

- La turtle descansa entre árboles (x=0, 2, 4...).
- Los saplings se plantan en x=1, 3, 5... (bloques impares), con tierra debajo (y=-1).
- Cofre detrás de la turtle (x=-1) para volcar logs.
- Espaciado entre árboles configurable; 2 es lo mínimo para que las hojas no bloqueen el paso.

## Layout (farmer)

La turtle está **un bloque encima** del farmland. Es decir: farmland a Y=0, cultivos creciendo a Y=1, turtle a Y=2.

```
vista lateral:
  turtle ------>         (Y=2)
  [crop][crop][crop]     (Y=1)
  [farm][farm][farm]     (Y=0)
   (agua cerca cada 9x9)
```

- Turtle arranca en la esquina del plot mirando +X.
- El plot se extiende `farmWidth` bloques en +X y `farmLength` bloques en +Z.
- Cofre detrás (en -X) para volcar la cosecha.

## Control remoto

Requiere un **wireless modem** en la turtle (upgrade slot) y otro en la computer desde la que controlas. El cliente funciona para **los tres programas** (mining / lumber / farmer): detecta el modo de cada turtle y renderiza campos específicos.

1. En la turtle: coloca el modem en uno de los slots de upgrade. Al arrancar verás que detecta `[Rem]` en el dashboard.
2. En la computer de control (o pocket con modem): copia `client.lua` (el installer lo baja) y ejecútalo.
3. `client` muestra un menú principal:
   - `[1]` Selector: lista de turtles en la red con modo [M/L/F], estado y fuel. Flechas para mover, Enter para entrar en la vista detallada.
   - `[2]` Fleet dashboard: tabla con todas las turtles a la vez. Pulsa `1-9` para hacer drill directo en una turtle.

### Navegación

- **Flechas + Enter** para selección en menús.
- **`B` / Backspace** vuelve atrás (single → selector, fleet/drill → fleet, selector → menú).
- **`Q`** sale del cliente desde cualquier pantalla.
- **`R`** refresca el escaneo/broadcast (desde selector y fleet).

### Comandos en la vista single (mining / lumber / farmer)

- `P` — pausa al próximo punto seguro
- `R` — resume
- `H` — vuelve a casa (descarga loot en cofre y termina)
- `S` — stop: guarda checkpoint y se queda quieta
- `Space` — pide refresh inmediato
- `B` — volver al selector
- `Q` — salir

### Campos por modo (vista single)

- **Mining**: progreso `currentStep / shaftLength`, patrón y ancho, stats `min/ore/cof/slot`, tamaño del ore map compartido.
- **Lumber**: modo grid/single, número de árboles, espaciado, flag bonemeal, contador `logs`.
- **Farmer**: dimensiones del plot, ciclo actual, fila en curso, contador `crops`.

La turtle hace broadcast del status cada 5s. Si hay varias turtles en rednet, `client` las lista con su hostname.

## Swarm (varias turtles cooperando)

Si tienes GPS activo (3+ computers fijas corriendo `gps host <x> <y> <z>`), las turtles comparten automáticamente un **ore map** en rednet:

- Cuando una turtle detecta un mineral, hace broadcast con su posición **absoluta**.
- Todas las turtles que escuchen lo guardan en su `state.oreMap`.
- Cuando una turtle llega y lo cava, hace broadcast de `ore_gone` y todas lo sacan.
- Al arrancar, una turtle nueva pide `sync_request` y las existentes le mandan su mapa.

En el dashboard verás `[GPS]` y `OreM:<N>` indicando cuántos ores compartidos conoce.

### Fleet mode en el cliente

`client` → elige `[2] Fleet dashboard`: lista todas las turtles de la red en tabla con posición world/local, fuel, estado, progreso y ores encontrados. Además muestra el mapa combinado de descubrimientos de todas las turtles.

Tecla `F` dentro del fleet mode: envía configuración a todas (feature preliminar — las turtles aún no auto-aplican; pendiente).

Lo que aún NO hace el swarm (pensado pero no implementado):
- Auto-navegar a un ore descubierto por otra turtle
- Job queue real (pedir "siguiente trabajo")
- Cofre de refuel común compartido
- Detección activa de turtles "muertas"

Las primitivas (`swarm.nearestUnclaimed`, `swarm.claimOre`) están listas para construir esto encima.

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
- [PPakalns/TreeFarm - tree farm CC](https://github.com/PPakalns/TreeFarm)
- [LemonKiwiCherry/computercraft-farm - farming programs](https://github.com/LemonKiwiCherry/computercraft-farm)
- [Promises/farming-turtle - farming turtle](https://github.com/Promises/farming-turtle)
- [HeshamSHY/Turtly-Farmer - wheat farming](https://github.com/HeshamSHY/Turtly-Farmer)
