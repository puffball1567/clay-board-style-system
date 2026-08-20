use std::env;

fn main() {
    println!("cargo:rerun-if-env-changed=CBSS_LIB_DIR");
    println!("cargo:rerun-if-env-changed=CBSS_STATIC");

    let Ok(directory) = env::var("CBSS_LIB_DIR") else {
        println!(
            "cargo:warning=CBSS_LIB_DIR is unset; final consumers must provide the CBSS library"
        );
        return;
    };

    println!("cargo:rustc-link-search=native={directory}");
    if env::var_os("CBSS_STATIC").is_some() {
        println!("cargo:rustc-link-lib=static=cbss");
        let target = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
        if target == "linux" {
            println!("cargo:rustc-link-lib=m");
            println!("cargo:rustc-link-lib=pthread");
            println!("cargo:rustc-link-lib=dl");
        }
    } else {
        println!("cargo:rustc-link-lib=dylib=cbss");
    }
}
