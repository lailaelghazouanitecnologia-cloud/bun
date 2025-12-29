# Zid - Ejemplo Completo

## 1. Data (Estructuras Inmutables)

```zig
const Data = struct {
    value: anytype,
    metadata: Metadata,

    pub fn of(value: anytype) Data {
        return .{ .value = value, .metadata = .{} };
    }

    pub fn map(self: Data, comptime f: fn(anytype) anytype) Data {
        return .{ .value = f(self.value), .metadata = self.metadata };
    }

    pub fn flatMap(self: Data, comptime f: fn(anytype) Data) Data {
        return f(self.value);
    }

    pub fn validate(self: Data, validator: Validator) Result(Data) {
        return validator.check(self);
    }

    pub fn unwrap(self: Data) @TypeOf(self.value) {
        return self.value;
    }
};

// Uso
const data = Data.of("1 + 2")
    .map(tokenize)
    .validate(token_rules)
    .map(parse)
    .validate(ast_rules)
    .map(emit);
```

## 2. Validator (Reglas de Validación)

```zig
const Validator = struct {
    rules: []const Rule,

    const Rule = struct {
        name: []const u8,
        check: fn(anytype) ?Error,
    };

    pub fn check(self: Validator, data: Data) Result(Data) {
        for (self.rules) |rule| {
            if (rule.check(data.value)) |err| {
                return .{ .err = .{ .rule = rule.name, .error = err } };
            }
        }
        return .{ .ok = data };
    }

    pub fn combine(a: Validator, b: Validator) Validator {
        return .{ .rules = a.rules ++ b.rules };
    }
};

// Definir validadores
const token_validator = Validator{ .rules = &.{
    .{ .name = "no_empty", .check = noEmptyTokens },
    .{ .name = "balanced_parens", .check = balancedParens },
    .{ .name = "valid_numbers", .check = validNumbers },
}};

const ast_validator = Validator{ .rules = &.{
    .{ .name = "no_orphan_nodes", .check = noOrphanNodes },
    .{ .name = "type_consistency", .check = typeConsistency },
}};

fn noEmptyTokens(tokens: []Token) ?Error {
    if (tokens.len == 0) return Error.empty_input;
    return null;
}

fn balancedParens(tokens: []Token) ?Error {
    var depth: i32 = 0;
    for (tokens) |t| {
        if (t.kind == .lparen) depth += 1;
        if (t.kind == .rparen) depth -= 1;
        if (depth < 0) return Error.unbalanced_parens;
    }
    if (depth != 0) return Error.unbalanced_parens;
    return null;
}
```

## 3. Compose (Pipeline)

```zig
const Compose = struct {
    stages: []const Stage,

    const Stage = struct {
        name: []const u8,
        transform: fn(anytype) anytype,
        validate: ?Validator = null,
        on_error: ?fn(Error) void = null,
    };

    pub fn pipeline(comptime stages: []const Stage) Compose {
        return .{ .stages = stages };
    }

    pub fn run(self: Compose, input: anytype) Result(anytype) {
        var data = Data.of(input);

        for (self.stages) |stage| {
            // Transform
            data = data.map(stage.transform);

            // Validate (si hay validador)
            if (stage.validate) |validator| {
                const result = data.validate(validator);
                if (result == .err) {
                    if (stage.on_error) |handler| {
                        handler(result.err);
                    }
                    return result;
                }
                data = result.ok;
            }
        }

        return .{ .ok = data.unwrap() };
    }

    // Comptime: genera pipeline optimizado
    pub fn compile(comptime self: Compose) fn(anytype) anytype {
        return struct {
            pub fn run(input: anytype) anytype {
                // Código generado en comptime, sin overhead de loop
                inline for (self.stages) |stage| {
                    // ...código inline optimizado...
                }
            }
        }.run;
    }
};

// Definir pipeline
const my_pipeline = Compose.pipeline(&.{
    .{ .name = "lex", .transform = lex, .validate = token_validator },
    .{ .name = "parse", .transform = parse, .validate = ast_validator },
    .{ .name = "analyze", .transform = analyze, .validate = semantic_validator },
    .{ .name = "emit", .transform = emit },
});

// Uso runtime
const result = my_pipeline.run("1 + 2 * 3");

// O compilar a función optimizada
const optimized_run = comptime my_pipeline.compile();
const result2 = optimized_run("1 + 2 * 3");
```

## 4. Templates en Comptime

```zig
// Templates son DATOS
const token_templates = .{
    .{ .name = "number", .pattern = "[0-9]+", .kind = .literal },
    .{ .name = "plus", .pattern = "+", .kind = .operator, .prec = 1 },
    .{ .name = "star", .pattern = "*", .kind = .operator, .prec = 2 },
    .{ .name = "lparen", .pattern = "(", .kind = .delimiter },
    .{ .name = "rparen", .pattern = ")", .kind = .delimiter },
};

// Comptime procesa templates → genera código optimizado
const Lexer = comptime blk: {
    var matchers: [token_templates.len]Matcher = undefined;

    for (token_templates, 0..) |template, i| {
        matchers[i] = Matcher.compile(template.pattern);
    }

    break :blk struct {
        const patterns = matchers;

        pub fn lex(source: []const u8) []Token {
            var tokens = ArrayList(Token).init();
            var pos: usize = 0;

            while (pos < source.len) {
                // Código generado inline para cada matcher
                inline for (patterns, 0..) |matcher, i| {
                    if (matcher.match(source[pos..])) |len| {
                        tokens.append(.{
                            .kind = token_templates[i].kind,
                            .start = pos,
                            .len = len,
                        });
                        pos += len;
                        break;
                    }
                }
            }

            return tokens.items;
        }
    };
};

// Runtime: usa código ya optimizado
const tokens = Lexer.lex("1 + 2 * 3");
```

## 5. Ejemplo Completo Integrado

```zig
const zid = @import("zid");

// ============ TEMPLATES (DATOS) ============

const tokens = .{
    .{ .name = "num", .pattern = "[0-9]+", .kind = .literal },
    .{ .name = "plus", .pattern = "+", .prec = 1, .assoc = .left },
    .{ .name = "star", .pattern = "*", .prec = 2, .assoc = .left },
    .{ .name = "lparen", .pattern = "(" },
    .{ .name = "rparen", .pattern = ")" },
};

const nodes = .{
    .{ .name = "Binary", .fields = .{ "left", "op", "right" } },
    .{ .name = "Literal", .fields = .{ "value" } },
    .{ .name = "Group", .fields = .{ "expr" } },
};

const rules = .{
    .{ .name = "expr", .produces = "Binary", .pattern = .{ "term", "plus", "term" } },
    .{ .name = "term", .produces = "Binary", .pattern = .{ "factor", "star", "factor" } },
    .{ .name = "factor", .alt = .{ "num", .{ "lparen", "expr", "rparen" } } },
};

const emit_js = .{
    .{ .node = "Binary", .format = "{left} {op} {right}" },
    .{ .node = "Literal", .format = "{value}" },
    .{ .node = "Group", .format = "({expr})" },
};

// ============ VALIDATORS ============

const token_rules = zid.Validator.init(&.{
    zid.rules.noEmpty,
    zid.rules.balancedDelimiters(.{ "(", ")" }),
});

const ast_rules = zid.Validator.init(&.{
    zid.rules.noOrphanNodes,
    zid.rules.validBinaryOps,
});

const semantic_rules = zid.Validator.init(&.{
    zid.rules.typeCheck,
});

// ============ COMPTIME: Genera código optimizado ============

const Lexer = comptime zid.Lexer.from(tokens);
const Parser = comptime zid.Parser.from(nodes, rules);
const Emitter = comptime zid.Emitter.from(emit_js);

// ============ COMPOSE: Pipeline ============

const pipeline = comptime zid.Compose.pipeline(&.{
    .{
        .name = "lex",
        .transform = Lexer.lex,
        .validate = token_rules,
    },
    .{
        .name = "parse",
        .transform = Parser.parse,
        .validate = ast_rules,
    },
    .{
        .name = "analyze",
        .transform = zid.analyze,
        .validate = semantic_rules,
    },
    .{
        .name = "optimize",
        .transform = zid.optimize,
        // Sin validación, paso opcional
    },
    .{
        .name = "emit",
        .transform = Emitter.emit,
    },
});

// Compilar pipeline a función optimizada
const process = comptime pipeline.compile();

// ============ RUNTIME: Ejecuta código optimizado ============

pub fn main() void {
    const source = "1 + 2 * 3";

    const result = process(source);

    switch (result) {
        .ok => |output| {
            print("Output: {s}\n", .{output});
            // Output: 1 + 2 * 3
        },
        .err => |e| {
            print("Error en {s}: {s}\n", .{ e.stage, e.message });
        },
    }
}
```

## 6. Flujo Visual

```
SOURCE: "1 + 2 * 3"
         │
         ▼
┌─────────────────────────────────────────────────────┐
│  STAGE: lex                                         │
│  ┌─────────────┐    ┌─────────────┐                │
│  │  transform  │───▶│  validate   │                │
│  │  Lexer.lex  │    │ token_rules │                │
│  └─────────────┘    └─────────────┘                │
│         │                  │                        │
│         │           ┌──────┴──────┐                │
│         │           │             │                │
│         ▼          .ok          .err → STOP        │
└─────────────────────────────────────────────────────┘
         │
         ▼
    [num, plus, num, star, num]
         │
         ▼
┌─────────────────────────────────────────────────────┐
│  STAGE: parse                                       │
│  ┌─────────────┐    ┌─────────────┐                │
│  │  transform  │───▶│  validate   │                │
│  │ Parser.parse│    │  ast_rules  │                │
│  └─────────────┘    └─────────────┘                │
└─────────────────────────────────────────────────────┘
         │
         ▼
    Binary(1, +, Binary(2, *, 3))
         │
         ▼
┌─────────────────────────────────────────────────────┐
│  STAGE: analyze                                     │
│  ┌─────────────┐    ┌─────────────┐                │
│  │  transform  │───▶│  validate   │                │
│  │  analyze    │    │semantic_rules│               │
│  └─────────────┘    └─────────────┘                │
└─────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────┐
│  STAGE: optimize (sin validación)                   │
│  ┌─────────────┐                                   │
│  │  transform  │                                   │
│  │  optimize   │                                   │
│  └─────────────┘                                   │
└─────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────┐
│  STAGE: emit                                        │
│  ┌─────────────┐                                   │
│  │  transform  │                                   │
│  │ Emitter.emit│                                   │
│  └─────────────┘                                   │
└─────────────────────────────────────────────────────┘
         │
         ▼
OUTPUT: "1 + 2 * 3"
```

## 7. Resumen

```
COMPTIME (compilación):
├── Templates → se procesan → código optimizado
├── Validators → se verifican reglas
└── Pipeline → se compila a función inline

RUNTIME (ejecución):
└── Solo ejecuta código ya optimizado
    (sin interpretar templates, sin loops de validación)

ESTRUCTURAS:
├── Data       → Envuelve valores, permite .map(), .validate()
├── Validator  → Lista de reglas, .check() retorna Result
└── Compose    → Pipeline de stages, .compile() genera código
```
