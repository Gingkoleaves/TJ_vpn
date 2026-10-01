#![cfg_attr(windows, windows_subsystem = "windows")]

use std::{env, path::Path, process::Command};

fn script_path(executable: &Path) -> Result<std::path::PathBuf, String> {
    let directory = executable
        .parent()
        .ok_or("Cannot locate package directory")?;
    for script in [directory.join("app/Gui.ps1"), directory.join("Gui.ps1")] {
        if script.is_file() {
            return Ok(script);
        }
    }
    Err("GUI script is missing. Extract the complete release ZIP before starting.".into())
}

fn launch() -> Result<(), String> {
    let arguments: Vec<String> = env::args().skip(1).collect();
    let smoke_test = arguments == ["--smoke-test"];
    if !arguments.is_empty() && !smoke_test {
        return Err("Supported option: --smoke-test".into());
    }
    let executable = env::current_exe().map_err(|error| error.to_string())?;
    let script = script_path(&executable)?;
    let system_root = env::var_os("SystemRoot").ok_or("Windows SystemRoot is unavailable")?;
    let powershell = Path::new(&system_root)
        .join("System32")
        .join("WindowsPowerShell")
        .join("v1.0")
        .join("powershell.exe");
    let mut command = Command::new(powershell);
    command.args(["-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File"]);
    command.arg(script);
    if smoke_test {
        command.arg("-SmokeTest");
    }
    command.current_dir(executable.parent().ok_or("Package directory missing")?);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000); // CREATE_NO_WINDOW; WinForms still displays normally.
    }
    let mut child = command.spawn().map_err(|error| error.to_string())?;
    if smoke_test && !child.wait().map_err(|error| error.to_string())?.success() {
        return Err("GUI smoke test failed".into());
    }
    Ok(())
}

#[cfg(windows)]
fn show_error(message: &str) {
    #[link(name = "user32")]
    unsafe extern "system" {
        fn MessageBoxW(
            window: *mut std::ffi::c_void,
            text: *const u16,
            caption: *const u16,
            kind: u32,
        ) -> i32;
    }
    let text: Vec<u16> = message.encode_utf16().chain(Some(0)).collect();
    let title: Vec<u16> = "Tongji VPN launcher"
        .encode_utf16()
        .chain(Some(0))
        .collect();
    // Both UTF-16 buffers are NUL terminated and live until MessageBoxW returns.
    unsafe {
        MessageBoxW(std::ptr::null_mut(), text.as_ptr(), title.as_ptr(), 0x10);
    }
}

#[cfg(not(windows))]
fn show_error(message: &str) {
    eprintln!("{message}");
}

fn main() {
    if let Err(error) = launch() {
        show_error(&error);
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_extracted_gui_is_reported_before_launch() {
        let root = env::temp_dir().join(format!("tongji-launcher-test-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        assert!(script_path(&root.join("TongjiVPN.exe")).is_err());
        std::fs::write(root.join("Gui.ps1"), "# fixture").unwrap();
        assert_eq!(
            script_path(&root.join("TongjiVPN.exe")).unwrap(),
            root.join("Gui.ps1")
        );
        std::fs::create_dir(root.join("app")).unwrap();
        std::fs::write(root.join("app/Gui.ps1"), "# current layout").unwrap();
        assert_eq!(
            script_path(&root.join("TongjiVPN.exe")).unwrap(),
            root.join("app/Gui.ps1")
        );
        std::fs::remove_file(root.join("app/Gui.ps1")).unwrap();
        std::fs::remove_dir(root.join("app")).unwrap();
        std::fs::remove_file(root.join("Gui.ps1")).unwrap();
        std::fs::remove_dir(root).unwrap();
    }
}
