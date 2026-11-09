use std::{env, fs, path::Path};

fn main() {
    // Embed every tweak script so the app ships as a single exe.
    let out = env::var("OUT_DIR").expect("OUT_DIR");
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("scripts").join("tweaks");
    let mut files: Vec<_> = fs::read_dir(&dir)
        .expect("scripts/tweaks")
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().map(|x| x == "ps1").unwrap_or(false))
        .collect();
    files.sort();
    let mut code = String::from("pub static TWEAK_SCRIPTS: &[(&str, &str)] = &[\n");
    for p in &files {
        let id = p.file_stem().unwrap().to_string_lossy();
        code.push_str(&format!("    ({:?}, include_str!({:?})),\n", id, p.to_string_lossy()));
    }
    code.push_str("];\n");
    fs::write(Path::new(&out).join("scripts.rs"), code).expect("write scripts.rs");
    println!("cargo:rerun-if-changed=scripts");
    println!("cargo:rerun-if-changed=app.manifest");

    let attrs = tauri_build::Attributes::new().windows_attributes(
        tauri_build::WindowsAttributes::new().app_manifest(include_str!("app.manifest")),
    );
    tauri_build::try_build(attrs).expect("failed to run tauri build script");
}
