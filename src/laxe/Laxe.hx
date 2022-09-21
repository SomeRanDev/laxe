package laxe;

#if (macro || laxeRuntime)

import laxe.parsers.ModuleParser;

import haxe.macro.Context;

import sys.FileSystem;

import haxe.io.Path;

var ClassPaths = [];
var Modules: Array<ModuleParser> = [];
var ModuleMap: Map<String, ModuleParser> = [];
var UseHaxeClassPaths = true;

final LaxePathExtension = "lx";

@:nullSafety(Strict)
function AddClassPath(p: String) {
	ClassPaths.push(p);
}

@:nullSafety(Strict)
function DisallowHaxeClassPaths() {
	UseHaxeClassPaths = false;
}

@:nullSafety(Strict)
function GetClassPaths() {
	final result = if(UseHaxeClassPaths) {
		Context.getClassPath().concat(ClassPaths);
	} else {
		ClassPaths;
	}
	final p = Context.definedValue("laxe-cp");
	if(p != null && p.length > 0) {
		return [p].concat(result);
	}
	return result;
}

@:nullSafety(Strict)
function ReadDirectory(path: String): Array<String> {
	return FileSystem.readDirectory(FileSystem.absolutePath(path));
}

@:nullSafety(Strict)
function Start() {
	final paths = GetClassPaths();
	for(p in paths) {
		final path = p.length > 0 ? p : "./";
		if(FileSystem.exists(path)) {
			LoadFiles(ReadDirectory(path), p);
		}
	}
	Compile();
}

@:nullSafety(Strict)
function LoadFiles(files: Array<String>, directoryString: String, packageString: String = "") {
	for(f in files) {
		final fullPath = Path.join([directoryString, f]);
		final packagePath = Path.join([packageString, f]);
		final p = new Path(fullPath);
		if(p.ext == LaxePathExtension) {
			LoadFile(fullPath, new Path(packagePath));
		} else if(FileSystem.isDirectory(fullPath)) {
			LoadFiles(ReadDirectory(fullPath), fullPath, packagePath);
		}
	}
}

@:nullSafety(Strict)
function LoadFile(f: String, p: Path) {
	if(!ModuleMap.exists(f)) {
		final m = new ModuleParser(f, p);
		Modules.push(m);
		ModuleMap.set(f, m);
	}
}

@:nullSafety(Strict)
function ApplyModifies() {
	for(m in Modules) {
		m.applyModifies(Modules);
	}
}

@:nullSafety(Strict)
function Compile() {
	for(m in Modules) {
		m.processModule();
	}
	ApplyModifies();
	for(m in Modules) {
		m.defineModule();
	}
}

#end
