# Turtle Multiprogram v1.3

Programas para turtles + dispositivos compañeros en **CC:Tweaked**, compartiendo la misma base (persistencia, movimiento seguro, control remoto por rednet y swarm opcional con GPS):

- **Mining** — branch / tunnel mining con auto-fuel y cofres inteligentes.
- **Lumber** — tala automatizada de árboles (grid o single con bonemeal).
- **Farmer** — cultivo automático de trigo, zanahoria, patata y remolacha.
- **Scout** — turtle con geoscanner que mapea el área y publica ores vía rednet. No mina.
- **Client** — dashboard interactivo en cualquier computer o pocket con modem.

Diseñado para **turtles no-advanced** (pantalla 39x13, sin color). Todo el renderizado usa solo caracteres ASCII.

## Rol persistente (desde v1.3)

Cada dispositivo elige su rol **una vez** en el primer boot y queda guardado en `/role.cfg`. A partir de ahí arranca directamente sin preguntar. Para cambiarlo: ejecuta `configure` en el shell.

- **Turtle**: wizard te pregunta rol (mining / lumber / farmer / scout) + parámetros del programa.
- **Pocket computer**: rol `client` auto-asignado; `startup` ejecuta el cliente directamente.
- **Computer normal**: rol `client` auto-asignado; arranca el dashboard al boot.

`/state.dat` sigue guardando el **progreso en vivo** (para resume tras crash o chunk-unload) y es independiente de `/role.cfg`.

## Qué hace (mining)

- **Branch mining** con ancho configurable (1x3 rápido o 3x3 completo): túnel principal con ramas laterales cada X bloques. El 3x3 cava todas las columnas correctamente (centro + laterales).
- **Resume tras apagado**: el estado se guarda en `/state.dat` cada paso. Si el chunk se descarga o la turtle se apaga, al reiniciar ofrece reanudar desde el último paso completado.
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

## Qué hace (scout)

El scout **no mina**: su trabajo es poblar el ore-map del swarm. Lleva **geoscanner + wireless modem** como upgrades (sin pico). Navega por el aire a una altura segura, baja a la altura de scan configurada, ejecuta `geoScanner.scan(radius)`, convierte los offsets relativos a coordenadas absolutas via GPS y broadcasta un `scan_report` batch con todos los ores encontrados.

Los mining turtles escuchan ese `scan_report` y lo mergean en su `oreMap` local. Así un scout mapea un área y **varios miners** la reciben sin gastar un slot de upgrade en geoscanner cada uno.

Tres patrones de patrulla seleccionables en el wizard:

- **Box** — rectángulo fijo (corner + ancho + largo) a una Y de scan, recorrido en serpentina con spacing configurable entre scans. Predecible, cubre un área definida.
- **Stationary** — se queda en un punto y scanea en loop. Útil si tienes un punto alto con vista a la zona.
- **Follow** — escucha los `status` broadcasts de miners activos y se coloca sobre el más reciente para scanear alrededor suyo. Requiere pathfinding básico: funciona mejor si el cielo está despejado.

El scout **no tiene pico**, así que no puede cavar. Si un bloque le bloquea el paso intenta subir unos bloques por encima antes de darse por vencido. Recomendable tenerlo operando por encima de la superficie del terreno.

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
├── startup.lua              ← entry point: dispatch segun /role.cfg
├── configure.lua            ← reconfigurar rol o params (shell command)
├── client.lua               ← dashboard remoto (computer / pocket)
├── install.lua              ← descarga auto-actualizable desde main
├── lib/                     ← modulos compartidos entre programas
│   ├── ui.lua               ← splash, menús, dashboard
│   ├── roleconfig.lua       ← lee/escribe /role.cfg + defaults
│   ├── config.lua           ← wizard + sub-menús por rol
│   ├── persist.lua          ← runtime state /state.dat (resume)
│   ├── peripherals.lua      ← detección Env Detector + Geo Scanner
│   ├── inventory.lua        ← refuel, filtrado, cofres, dumpInto
│   ├── movement.lua         ← movimiento seguro + tracking XYZ
│   ├── remote.lua           ← rednet listener + status broadcast
│   └── swarm.lua            ← GPS + ore map + scan_report + peers
├── mining/mining.lua        ← branch/tunnel + return-to-start
├── lumber/lumber.lua        ← tala grid/single + replant
├── farmer/farmer.lua        ← serpentina NxM + harvest+replant
├── scout/scout.lua          ← geoscanner + box/stationary/follow
└── README.md
```

## Instalación

La forma recomendada es usar `install.lua`, que se auto-actualiza desde `main` de GitHub y crea las carpetas `lib/`, `mining/`, `lumber/` y `farmer/`:

```
pastebin get <ID> install
install
```

Cada vez que ejecutes `install` la turtle comprueba si `install.lua` ha cambiado en remoto, se auto-actualiza primero y luego descarga el resto. Un commit a `main` es efectivamente un deploy.

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

**Scout:**
- **NO necesita pico**. Upgrades: **Geo Scanner + Wireless Modem**
- **GPS activo**: mínimo 3 computers fijas corriendo `gps host <x> <y> <z>` en rango
- **Coal / Charcoal** para auto-refuel
- Zona de operación **con cielo despejado** (no puede cavar)

## Cómo usar

1. Coloca el dispositivo (turtle / pocket / computer) en su posición inicial.
2. Mete el inventario necesario (combustible + items del rol).
3. Ejecuta `install` si aún no lo has hecho. La primera vez el dispositivo arranca el **wizard** y te pregunta rol + parámetros.
4. A partir del segundo boot, el dispositivo arranca **directamente** en su rol.
5. Para cambiar algo: ejecuta `configure` en el shell y reinicia.

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

## Swarm P2P (varias turtles cooperando)

Con GPS activo (3+ computers fijas corriendo `gps host <x> <y> <z>`), las turtles mantienen un **ore map compartido** sin servidor central. Toda la comunicación es peer-to-peer sobre rednet.

### Deltas en tiempo real

- `ore_spotted` / `ore_gone` se broadcastan cuando una turtle encuentra o cava un ore.
- `scan_report` batch del scout publica varios ores en un solo mensaje.

### Sync inteligente al unirse una turtle nueva

1. **Digest**: la nueva broadcasta `sync_request` con su `{count, latest}`.
2. **Offer**: las peers que tengan más o más reciente contestan con `sync_offer` + su propio digest.
3. **Ack**: tras 3s la nueva elige el mejor y manda `sync_ack` solo a ese.
4. **Chunked dump**: el elegido envía `sync_chunk` paginados (100 entradas/pg) con solo lo que falta (delta por `seenAt`). El último chunk lleva los tombstones.

Solo un peer hace el dump, el resto se calla. Bandwidth O(1) en número de peers.

### Tombstones (ores ya minados)

Cuando una turtle cava un ore, además de borrar del mapa registra un **tombstone** con TTL de 10 min. Si llega después un `ore_spotted` o un chunk de sync con ese ore, se **rechaza** salvo que el `seenAt` sea posterior al tombstone (respawn raro). Esto evita que un peer con información stale re-introduzca ores ya consumidos.

### Gossip anti-entropy (auto-healing)

Cada 120s cada turtle elige aleatoriamente un peer conocido y le manda un `gossip_ping` con su digest. Si el otro detecta que tiene info más reciente, responde con un `sync_chunk` delta. Garantiza convergencia en 1-2 ciclos tras una reconexión o partición de red.

### Versión por entrada

Cada ore en el mapa lleva `seenAt` (epoch unix). Merge es always **last-writer-wins**. Los chunks de sync preservan el `seenAt` original, por lo que un peer viejo no pisa datos recientes.

### Métricas visibles

El `client` muestra en la vista single:
- `peers=N` — cuántos peers activos (vistos en los últimos 60s)
- `tomb=N` — tombstones activos
- `sync=phase` — fase del handshake si hay uno en curso (`awaiting_offers` / `awaiting_chunks`) o `idle`

En el dashboard de la propia turtle verás `[GPS]` y `OreM:<N>` indicando cuántos ores compartidos conoce.

### Backwards compat

El protocolo viejo `sync_dump` (full map en un mensaje) se sigue procesando para interoperar con turtles que aún no tengan el upgrade P2P.

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
