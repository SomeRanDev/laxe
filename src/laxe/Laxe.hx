package laxe;

#if macro

import laxe.parsers.ModuleParser;

import haxe.macro.Compiler;
import haxe.macro.Context;

import sys.FileSystem;

import haxe.io.Path;

var ClassPaths = [];

final LaxePathExtension = "lx";

function AddClassPath(p: String) {
	ClassPaths.push(p);
}

function GetClassPaths() {
	final p = Context.definedValue("laxe-cp");
	if(p != null) {
		return [p].concat(ClassPaths);
	}
	return ClassPaths;
}

function Start() {
	final paths = GetClassPaths();
	for(p in paths) {
		LoadFiles(FileSystem.readDirectory(p), p);
	}
}

function LoadFiles(files: Array<String>, directoryString: String) {
	for(f in files) {
		final fullPath = Path.join([directoryString, f]);
		trace(directoryString, fullPath);
		final p = new Path(fullPath);
		if(p.ext == LaxePathExtension) {
			LoadFile(f, p);
		} else if(FileSystem.isDirectory(f)) {
			LoadFiles(FileSystem.readDirectory(f), f);
		}
	}
}

function LoadFile(f: String, p: Path) {
	final m = new ModuleParser(f, p);
	m.defineModule();
}

#end
