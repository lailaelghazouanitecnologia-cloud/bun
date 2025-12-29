# Zid - Modular Runtime Architecture

## Estructura de Modulos

```
zig/
├── docs/
│   ├── README.md           # Este archivo
│   ├── 01_CORE.md          # Sistema base
│   ├── 02_PLUGIN_SYSTEM.md # Sistema de plugins
│   ├── 03_CLI.md           # Comandos dinamicos
│   ├── 04_IO.md            # I/O asincrono
│   ├── 05_RESOLVER.md      # Resolucion de modulos
│   ├── 06_LANGUAGE.md      # Plugins de lenguaje
│   ├── 07_TARGET.md        # Plugins de target/emision
│   └── 08_CONFIG.md        # Sistema de configuracion
└── src/                    # (futuro) Codigo fuente Zid
```

## Modulos de Zid

| # | Modulo | Lineas Est. | Dependencias | Descripcion |
|---|--------|-------------|--------------|-------------|
| 1 | Core | ~2,000 | ninguna | Tipos base, memoria, errores |
| 2 | Plugin System | ~3,000 | Core | Registro y carga de plugins |
| 3 | CLI | ~2,000 | Core, Plugin | Router de comandos dinamico |
| 4 | IO | ~4,000 | Core | I/O asincrono cross-platform |
| 5 | Resolver | ~3,000 | Core, IO | Resolucion de modulos generica |
| 6 | Language | ~1,500 | Core, Plugin | Interface para parsers |
| 7 | Target | ~1,500 | Core, Plugin | Interface para emitters |
| 8 | Config | ~1,000 | Core | Carga de configuracion |

**Total estimado: ~18,000 lineas**

## Grafo de Dependencias

```
                    ┌──────────┐
                    │   CORE   │
                    └────┬─────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    ┌────▼────┐    ┌─────▼─────┐   ┌─────▼─────┐
    │   IO    │    │  Plugin   │   │  Config   │
    └────┬────┘    │  System   │   └───────────┘
         │         └─────┬─────┘
         │               │
    ┌────▼────┐    ┌─────┴─────┐
    │Resolver │    │           │
    └─────────┘    │     ┌─────▼─────┐
                   │     │    CLI    │
             ┌─────▼───┐ └───────────┘
             │         │
        ┌────▼───┐ ┌───▼────┐
        │Language│ │ Target │
        └────────┘ └────────┘
```

## Principios de Diseno

1. **Minimalismo**: Solo lo esencial en core
2. **Pluggable**: Todo lo demas son plugins
3. **Zero-config**: Funciona sin configuracion
4. **Multi-target**: Emite a cualquier lenguaje
5. **Cross-platform**: Linux, macOS, Windows

## Flujo de Datos

```
Input File → [Language Plugin] → AST → [Transform Plugins] → AST' → [Target Plugin] → Output
     │              │                         │                           │
     │         tokenize()                transform()                   emit()
     │         parse()                                            generateSourceMap()
     │
   Resolver (encuentra el archivo)
```

## Proximos Pasos

1. Leer cada documento de modulo
2. Entender responsabilidades
3. Identificar interfaces
4. Comenzar implementacion

---
*Zid: Un runtime para todos los lenguajes*
