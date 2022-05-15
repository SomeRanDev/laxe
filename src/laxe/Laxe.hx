package laxe;

#if (macro || laxeRuntime)

import laxe.parsers.ModuleParser;

import haxe.macro.Context;

import sys.FileSystem;

import haxe.io.Path;

var ClassPaths = [];
var Modules: Array<ModuleParser> = [];

final LaxePathExtension = "lx";

@:nullSafety(Strict)
function AddClassPath(p: String) {
	ClassPaths.push(p);
}

@:nullSafety(Strict)
function GetClassPaths() {
	final p = Context.definedValue("laxe-cp");
	if(p != null) {
		return [p].concat(ClassPaths);
	}
	return ClassPaths;
}

@:nullSafety(Strict)
function Start() {
	final paths = GetClassPaths();
	for(p in paths) {
		LoadFiles(FileSystem.readDirectory(p), p);
	}
	Compile();
}

@:nullSafety(Strict)
function LoadFiles(files: Array<String>, directoryString: String) {
	for(f in files) {
		final fullPath = Path.join([directoryString, f]);
		final p = new Path(fullPath);
		if(p.ext == LaxePathExtension) {
			LoadFile(fullPath, p);
		} else if(FileSystem.isDirectory(fullPath)) {
			LoadFiles(FileSystem.readDirectory(fullPath), fullPath);
		}
	}
}

@:nullSafety(Strict)
function LoadFile(f: String, p: Path) {
	final m = new ModuleParser(f, p);
	Modules.push(m);
}

@:nullSafety(Strict)
function Compile() {
	for(m in Modules) {
		m.applyMeta();
		m.defineModule();
	}
}

#end
