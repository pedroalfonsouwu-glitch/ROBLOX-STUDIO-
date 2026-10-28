# Hombre Lobo — Bosque de la Luna

Juego de Roblox Studio con mapa procedural, rondas de Hombre Lobo y Ejecutores, misiones, inventario y opción **Jugar con IA** para probar en solitario.

La actualización **v19** se publicó el 28 de octubre de 2026 en [la experiencia privada](https://www.roblox.com/games/77968787658281). Corrige el resultado personal al morir o ganar, muestra la facción y los ganadores, conserva la pantalla durante el respawn y anima al equipo ganador con una pista del catálogo de Roblox.

## Probar

Abrí el juego publicado con una cuenta que tenga acceso o abrí `build/HombreLobo.rbxlx` en Roblox Studio. En solitario, elegí **Jugar con IA**. Para una ronda normal con otras personas, usá **Server & Clients** con al menos dos jugadores.

En PC: **E** interactuar, **F** atacar, **Q** habilidad, **B** inventario, **C** defender, **X** esquivar y **V** mostrar el alcance. En teléfono se usa el joystick de Roblox y el menú lateral de acciones.

## Proyecto y build

El proyecto activo es `default.project.json`; Rojo 7.7.1 genera el archivo local:

```powershell
rojo build default.project.json -o build/HombreLobo.rbxlx
```

El archivo generado se guarda localmente y no se versiona. El proyecto conserva la plantilla original en las rutas antiguas, pero `default.project.json` importa el juego Hombre Lobo.

El árbol `assets/roblox/Tree.rbxmx` procede de Nature Kit de Kenney, bajo CC0. Su licencia y datos de conversión están junto al asset; el OBJ original se puede convertir con `python tools/convert_cc0_obj.py`. La música de victoria es **Favela Funk** de APMOfficial, Creator Store ID `1841682637`; es un asset gratuito para experiencias Roblox, no dominio público. La danza es una adaptación manual para rigs R6 y R15 de la referencia indicada por el usuario, no un emote descargado.

## Comprobación de esta versión

- 27/27 verificaciones nativas de resultado en Studio, cubriendo victoria y derrota de ambos roles con combates y respawns naturales.
- 4/4 verificaciones del baile en rigs humano/lobo R6/R15.
- Publicación nativa v19 confirmada y lectura nueva de Roblox: 28/28 comprobaciones de clases y fuentes para las 14 fuentes del proyecto.

Estas comprobaciones no son un benchmark de rendimiento. No se hicieron pruebas nuevas con teléfono físico, carga distribuida, Player sostenido ni DataStore real en esta tanda.
