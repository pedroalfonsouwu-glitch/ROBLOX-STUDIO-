# Resultados y celebración — v13

La actualización v19 se publicó el 28 de octubre de 2026 a las 16:20 (Argentina) en [la experiencia privada](https://www.roblox.com/games/77968787658281). Conserva el mismo lugar y sus permisos; no se creó otra experiencia.

## Resultado personal

El servidor conserva el rol de la ronda incluso después de que el jugador muere y pasa a espectador. El panel personal presenta **VICTORIA** o **DERROTA**, la facción ganadora y sus nombres; cuando Luna gana sola, aparece **Ganó Luna (IA)**. La cámara sigue al ganador que celebra y vuelve al personaje actual cuando acaba la escena. El panel sobrevive el respawn automático.

Se comprobaron los cuatro casos reales: Ejecutor gana, Hombre Lobo gana, Ejecutor pierde ante Luna y Hombre Lobo pierde ante Luna. La prueba nativa de Studio completó ocho rondas —cuatro repeticiones naturales mientras se sorteaban los roles— y **27/27 comprobaciones**. El auditor observó daño y muerte normales, respawn real, resultado privado, cámara y sonido; no escribió Health ni roles, no llamó a `LoadCharacter` ni sustituyó la cámara de producción. No hubo errores de scripts y las 14 fuentes temporales de prueba se restauraron.

La primera observación cerraba 1,2 s después de terminar la pantalla; una recreación natural del personaje llegó 11,1 s después de la muerte, por lo que la prueba la clasificó prematuramente como fallo. El auditor ahora mantiene la observación hasta `Players.RespawnTime + 12 s`, registra `Died → CharacterAdded` y exige un personaje nuevo con vida positiva, sin forzar la recarga. La repetición corregida pasó **27/27 comprobaciones** sin errores de scripts; no hizo falta cambiar el código del juego.

## Baile y audio

La coreografía es una adaptación manual de 21 poses tomadas como referencia del [video indicado por el usuario](https://www.youtube.com/shorts/bTu6kDbRigo). Se redujo el vaivén de piernas; se anima el cuerpo sin trasladar al ganador fuera del escenario. La prueba separada verificó los cuatro rigs humano/lobo R6/R15: **4/4**, articulaciones móviles y marcos de reposo intactos. No es un emote descargado ni una captura exacta del video.

La pista es [**Favela Funk**, de Henry Richard Obree Parsley / APMOfficial](https://create.roblox.com/store/asset/1841682637), ID `1841682637`, ofrecida gratis en Creator Store para usar en experiencias Roblox. No se distribuye el audio original del video. El fragmento se inicia en 8,103 s; el audio se acelera a `PlaybackSpeed = 1.3359375` para acompañar la referencia de movimiento y se detiene a los cinco segundos. Roblox documenta el uso de [audio de Creator Store](https://create.roblox.com/docs/audio/assets) y el efecto de [`Sound.PlaybackSpeed`](https://create.roblox.com/docs/reference/engine/classes/Sound#PlaybackSpeed).

## Publicación y lectura

Studio confirmó **PublishSuccessful** para el lugar 77968787658281 y anunció la versión nativa **v19**. Después, una sesión nueva de Studio leyó el lugar publicado: **28/28 verificaciones** de clases y fuentes, **14/14 fuentes idénticas** al candidato y la misma huella fuente. En el contexto de lectura del editor, Roblox devolvió `PlaceVersion = 0` como metadato no disponible; por eso la versión 19 se basa en el registro nativo de publicación, no en ese campo.

El build local de Rojo contiene las mismas 14 fuentes y superó las comprobaciones finales de conservación. Los originales, backups y los archivos históricos permanecieron intactos.

## Alcance

La prueba se ejecutó en Roblox Studio con un jugador humano y la opción de Luna IA; no equivale a dos dispositivos conectados por red. No se midieron FPS de Player, teléfonos físicos ni carga distribuida. DataStore real tampoco se volvió a probar en esta tanda. Por lo tanto, esta publicación no afirma mejoras de rendimiento ni valida esos entornos.
