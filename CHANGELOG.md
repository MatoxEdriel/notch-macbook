# Changelog

Todos los cambios notables de NotchBar se documentan aquí.

## [Novedad] - 2026-11-06

### Añadido
- **Pestaña de Docker (solo visual):** ahora puedes ver qué contenedores están corriendo directamente en el notch. Muestra la imagen (p. ej. `mongo:8.0`), el nombre y el estado de cada contenedor.
- Ballena de Docker en **pixel art**, fiel al logo oficial, con degradado azul. Se apaga a gris cuando no hay contenedores activos o Docker no está en ejecución.
- Fondo del notch con un degradado azul Docker suave en esa pestaña.
- Solo lectura: no se pueden iniciar ni detener contenedores desde el notch.

### Rendimiento
- Docker solo se consulta mientras el notch está abierto (una consulta cada 4 s); con el notch cerrado no se lanza ningún proceso.
