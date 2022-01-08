use object::RelocationTarget;
use object::{Object, ObjectSection, ObjectSymbol, SectionIndex};
use std::collections::{HashMap, HashSet};
use std::error::Error;
use std::fs;

type Result<T> = std::result::Result<T, Box<dyn Error>>;

struct SectionDep {
    deps: HashMap<SectionIndex, HashSet<SectionIndex>>,
}

impl SectionDep {
    fn reachable(&self, roots: Vec<SectionIndex>) -> HashSet<SectionIndex> {
        let mut queue = roots;
        let mut visited = HashSet::new();
        while let Some(index) = queue.pop() {
            if visited.contains(&index) {
                continue;
            }
            visited.insert(index);
            self.deps.get(&index).map(|deps| queue.extend(deps.iter()));
        }
        visited
    }

    fn find_rev_deps(&self, dep: SectionIndex) -> Vec<SectionIndex> {
        let mut rev_deps = Vec::new();
        for (section, deps) in self.deps.iter() {
            if deps.contains(&dep) {
                rev_deps.push(*section);
            }
        }
        rev_deps
    }
}

fn compute_renames(file: &object::File) -> Result<Vec<(String, String)>> {
    // Collect the list of unlikely sections.
    let mut unlikely_sections = HashSet::new();
    for section in file.sections() {
        let name = section.name()?;
        if name.starts_with(".text.unlikely") {
            unlikely_sections.insert(section.index());
        }
        // Force all unwind mechanisms to be cold.
        if name.starts_with(".text._Unwind_") || name == ".text.rust_eh_personality" {
            unlikely_sections.insert(section.index());
        }
    }

    // Build dependency graph of sections.
    // No filtering should take place here as .text can depend on another .text
    // through .data.
    let mut dep_graph = HashMap::new();
    let mut hot_dep_graph = HashMap::new();
    for section in file.sections() {
        let mut targets = HashSet::new();
        for (_, relocation) in section.relocations() {
            let section = match relocation.target() {
                RelocationTarget::Symbol(idx) => {
                    let symbol = file.symbol_by_index(idx)?;
                    // Ignore the edge to main, which is handled specially.
                    if symbol.name()? == "main" {
                        continue;
                    }
                    symbol.section_index()
                }
                RelocationTarget::Section(section) => Some(section),
                _ => None,
            };
            if let Some(section) = section {
                targets.insert(section);
            }
        }
        if !targets.is_empty() {
            hot_dep_graph.insert(
                section.index(),
                targets.difference(&unlikely_sections).copied().collect(),
            );
            dep_graph.insert(section.index(), targets);
        }
    }
    let deps = SectionDep { deps: dep_graph };
    let hot_deps = SectionDep {
        deps: hot_dep_graph,
    };

    // Find the section that contains the entry point.
    let mut root = Vec::new();
    let mut hot_root = Vec::new();
    let mut init_root = Vec::new();
    for symbol in file.symbols() {
        match symbol.name()? {
            "_start" | "main_hot" => {
                root.push(symbol.section_index().unwrap());
                hot_root.push(symbol.section_index().unwrap());
            }
            "rust_eh_personality" => {
                root.push(symbol.section_index().unwrap());
            }
            "main" => {
                init_root.push(symbol.section_index().unwrap());
            }
            _ => (),
        }
    }
    let reachable = deps.reachable(root);
    let hot_reachable = hot_deps.reachable(hot_root);
    let init_reachable: HashSet<_> = deps.reachable(init_root);

    let mut renames = Vec::new();
    for section in file.sections() {
        let name = section.name()?;

        // Decompose name into segments, e.g.
        //   ".text.foo" -> ("text", "foo")
        //   ".rodata.foo" -> ("rodata", "foo")
        let mut segments = name.splitn(3, '.');
        if segments.next() != Some("") {
            continue;
        }
        let primary = match segments.next() {
            Some(s) => s,
            None => continue,
        };
        let secondary = match segments.next() {
            Some(s) => s,
            None => continue,
        };

        if primary != "text" && primary != "rodata" {
            continue;
        }
        let mut prefix = "";
        let mut symbol = secondary;
        if secondary.starts_with("unlikely.") {
            prefix = "unlikely.";
            symbol = &secondary[9..];
        } else if secondary.starts_with("startup.") {
            prefix = "startup.";
            symbol = &secondary[7..];
        }

        let new_prefix = if hot_reachable.contains(&section.index()) {
            ""
        } else if reachable.contains(&section.index()) {
            "unlikely."
        } else if init_reachable.contains(&section.index()) {
            "startup."
        } else {
            prefix
        };
        if prefix != new_prefix {
            renames.push((
                format!(".{}.{}{}", primary, prefix, symbol),
                format!(".{}.{}{}", primary, new_prefix, symbol),
            ));
        }
    }

    Ok(renames)
}

/// Reads a file and displays the content of the ".boot" section.
fn main() -> Result<()> {
    let mut args = std::env::args();
    args.next();
    let mut stage1_args = Vec::new();
    let mut stage2_args = Vec::new();
    while let Some(arg) = args.next() {
        match &*arg {
            "--eh-frame-hdr" => {
                stage2_args.push(arg);
            }
            "-o" => {
                stage2_args.push(arg);
                stage2_args.push(args.next().unwrap());
            }
            "-T" => {
                stage2_args.push(arg);
                stage2_args.push(args.next().unwrap());
            }
            x if x.starts_with("-o") || x.starts_with("-T") => {
                stage2_args.push(arg);
            }
            _ => {
                stage1_args.push(arg);
            }
        }
    }

    // Probe the linker name.
    let linker = match std::process::Command::new("riscv64-unknown-linux-gnu-ld").arg("-v").output() {
        Ok(_) => "riscv64-unknown-linux-gnu-ld",
        Err(_) => "riscv64-linux-gnu-ld",
    };

    // Stage 1: First link everything in relocatable mode into a single object file to aid processing.
    //
    // To do this we need to filter out -o options from the linker command line.
    let status = std::process::Command::new(linker)
        .arg("-r")
        .arg("-o")
        .arg("output.elf.tmp")
        .arg("-e")
        .arg("_start")
        .args(stage1_args)
        .status()?;
    if !status.success() {
        std::process::exit(status.code().unwrap_or(1));
    }

    let bin_data = fs::read("output.elf.tmp")?;
    let file = object::File::parse(&*bin_data)?;
    let renames = compute_renames(&file)?;

    let mut ld = "SECTIONS\n{\n".to_owned();
    for (old_name, new_name) in renames {
        ld.push_str(&format!("\t{} : {{ *({}) }}\n", new_name, old_name));
    }
    ld.push_str("}\n");
    fs::write("linker.ld.tmp", ld)?;

    // Perform section renaming using generated linker scripts.
    //
    // Use this approach instead of writing out ELF files outselves using `object`
    // for reduced complexity and improved robustness.
    let status = std::process::Command::new(linker)
        .arg("-r")
        .arg("-Tlinker.ld.tmp")
        .arg("output.elf.tmp")
        .arg("-o")
        .arg("renamed.elf.tmp")
        .status()?;
    if !status.success() {
        std::process::exit(status.code().unwrap_or(1));
    }

    // Stage 2: Complete linking.
    let status = std::process::Command::new(linker)
        .arg("renamed.elf.tmp")
        .args(stage2_args)
        .status()?;
    if !status.success() {
        std::process::exit(status.code().unwrap_or(1));
    }

    // Clean up temporary files.
    fs::remove_file("output.elf.tmp")?;
    fs::remove_file("linker.ld.tmp")?;
    fs::remove_file("renamed.elf.tmp")?;
    Ok(())
}
