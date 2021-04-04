id: 0wttwf9snyho1o7kxhvv0xv3lg6v6naj71rmu8iw2sqt1sn5
name: wasm3
main: src/main.zig
dependencies:
- src: git https://github.com/wasm3/wasm3.git
  name: wasm3
  c_include_dirs:
  - source/
  c_source_files:
  - source/m3_api_libc.c
  - source/m3_api_meta_wasi.c
  - source/m3_api_tracer.c
  - source/m3_api_uvwasi.c
  - source/m3_api_wasi.c
  - source/m3_bind.c
  - source/m3_code.c
  - source/m3_compile.c
  - source/m3_core.c
  - source/m3_emit.c
  - source/m3_env.c
  - source/m3_exec.c
  - source/m3_info.c
  - source/m3_module.c
  - source/m3_optimize.c
  - source/m3_parse.c

