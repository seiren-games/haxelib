package tools.haxelib;

import haxe.ds.StringMap;
import tools.haxelib.Main;
import sys.FileSystem;


#if macro
import Type.enumParameters in ep;
import haxe.macro.TypeTools;
import haxe.macro.Type.BaseType;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type in MType;
#end


interface IVcs
{
	public var name(default, null):String;
	public var directory(default, null):String;
	public var executable(default, null):String;
	public var internalDirectory(default, null):String;

	public var available(get_available, null):Bool;


	// clone repo into CWD/{directory}
	public function clone(?cwd:String):Void;

	// check available updates for repo in CWD/{directory}
	public function updatable(?cwd:String):Void;

	/**
		Update to HEAD repo in `cwd` or `cwd`/{directory}.
		@param cwd is optional and if not passed it will work in current CWD.
		Otherwise CWD will be temporally changed to `cwd` and restored when job is complete.
	**/
	public function update(?cwd:String):Void;

	// reset all changes in repo in CWD/{directory}
	public function reset(?cwd:String):Void;
}


@:enum abstract VcsID(String) to String
{
	var Hg = "hg";
	var Git = "git";
}

enum VcsError
{
	VcsUnavailable(vcs:Vcs);
}


#if !macro
@:autoBuild(tools.haxelib.Vcs.staticRegistration()) #end
class Vcs
{
	#if macro
	static public function staticRegistration():Array<Field>
	{
		var type = Context.getLocalType();
		var typeRef:String = Type.enumParameters(type)[0];
		var classType = TypeTools.getClass(type);
		var fields = Context.getBuildFields();
		var lines = [];

		// get current executable:
		var constructor:Function;
		for(field in fields)
			if(field.name == "new" && field.kind.match(FieldType.FFun))
				constructor = ep(field.kind)[0];

		// without constructor:
		if(constructor == null)
			Context.error('${typeRef} should contain a constructor like all other subclasses of Vcs.', Context.currentPos());
		// constructor with args:
		if(constructor.args.length > 0)
			Context.error('Constructor of ${typeRef} should not require arguments', Context.currentPos());


		// get super call in constructor:
		var superCallExpr:ExprDef;
		function searchSuperCall(expr:ExprDef, next:Dynamic):Null<ExprDef>
		{
			switch(expr)
			{
				case ExprDef.EBlock(exprs):
					for(e in exprs)
					{
						var result = next(e.expr, next);
						if(result != null)
							return result;
					}

				case ExprDef.ECall(e, params):
					if(e.expr.match(ExprDef.EConst))
					{
						var c:Constant = ep(e.expr)[0];
						if(c.match(Constant.CIdent) && ep(c)[0] == "super")
							return expr;
					}
				default: return null;
			}
			return null;
		}
		superCallExpr = searchSuperCall(constructor.expr.expr, searchSuperCall);

		// without super Call:
		if(superCallExpr == null)
			Context.error('Constructor of ${typeRef} should call super.', Context.currentPos());

		// get first arg of super call:
		//XXX: optimize it:
		var vcsName:String = ep(ep(ep(superCallExpr)[1][0].expr)[0])[0];
		var typePath:TypePath = {name:classType.name, pack:classType.pack};
		var factory = macro function():Vcs
		{
			var result:Vcs = $p{["Vcs", "reg_inst"]}.get('$vcsName');
			if(result != null)
				return result;
			else
			{
				result = new $typePath();
				$p{["Vcs", "reg_inst"]}.set('$vcsName', result);
			}
			return result;
		}

		//TODO: search existing `__init__` => add to top of it's block.
		var regCall = macro $p{["Vcs", "reg"]}.set('$vcsName', $factory);
		lines.push(regCall);
		fields.push({
			            name: "__init__",
			            access: [APublic, AStatic],
			            pos: Context.currentPos(),
			            kind: FFun({
				                       args: [],
				                       expr: $b{lines[0]},
				                       params: [],
				                       ret: null
			                       })
		            });
		// dev-degug //
		/*var moduleName = Context.getLocalModule();
		var module = Context.getModule(moduleName);
		trace('[!!!] Module "$moduleName" contain ${module.length} types.');
		for(t in module)
			trace(t);*/
		// end //

		return fields;
	}
	#end

	//----------- properties, fields ------------//

	public var name(default, null):String;
	public var directory(default, null):String;
	public var executable(default, null):String;

	public var available(get_available, null):Bool;
	private var availabilityChecked:Bool = false;
	private var executableSearched:Bool = false;

	//TODO: change key:String to key:VcsID:
	private static var reg:Map<String, Void -> Vcs>;
	private static var reg_inst:Map<String, Vcs>;


	//private var cwd(get_cwd, set_cwd):String;

	//--------------- constructor ---------------//

	public static function __init__()
	{
		reg = new StringMap();
		reg_inst = new StringMap();
	}


	private function new(directory:String, executable:String, name:String)
	{
		this.name = name;
		this.directory = directory;
		this.executable = executable;
	}


	//----------------- static ------------------//

	public static function get(executable:VcsID):Null<Vcs>
	{
		if(reg.exists(executable))
			return reg.get(executable)();
		else return null;
	}

	public static function getVcsForDevLib(libPath:String):Null<Vcs>
	{
		for(k in reg.keys())
		{
			if(FileSystem.exists(libPath + "/" + k) && FileSystem.isDirectory(libPath + "/" + k))
				return reg.get(k)();
		}
		return null;
	}


	//--------------- initialize ----------------//

	private function searchExecutable():Void
	{
		executableSearched = true;
	}

	private function checkExecutable():Bool
	{
		available =
		executable != null && try
		{
			cmd(executable, []);
			true;
		}
		catch(e:Dynamic) false;
		availabilityChecked = true;

		if(!available && !executableSearched)
			searchExecutable();

		return available;
	}

	@:final function get_available():Bool
	{
		if(!availabilityChecked)
			checkExecutable();
		return this.available;
	}

	//----------------- ctrl -------------------//

	private function cmd(cmd:String, args:Array<String>)
	{
		var p = new sys.io.Process(cmd, args);
		var code = p.exitCode();
		return {code:code, out:code == 0 ? p.stdout.readAll().toString() : p.stderr.readAll().toString()};
	}

	public function cloneToCwd()
	{
		throw "This method must be overriden.";
	}

	public function updateInCwd(libName:String):Bool
	{
		throw "This method must be overriden.";
		return false;
	}


	public function toString():String
	{
		return Type.getClassName(Type.getClass(this));
	}
}


class Git extends Vcs
{
	public function new()
		super("git", "git", "Git");

	override private function searchExecutable():Void
	{
		super.searchExecutable();

		if(available)
			return;

		// if we have already msys git/cmd in our PATH
		var match = ~/(.*)git([\\|\/])cmd$/;
		for(path in Sys.getEnv("PATH").split(";"))
		{
			if(match.match(path.toLowerCase()))
			{
				var newPath = match.matched(1) + executable + match.matched(2) + "bin";
				Sys.putEnv("PATH", Sys.getEnv("PATH") + ";" + newPath);
			}
		}
		if(checkExecutable())
			return;
		// look at a few default paths
		for(path in ["C:\\Program Files (x86)\\Git\\bin", "C:\\Progra~1\\Git\\bin"])
			if(FileSystem.exists(path))
			{
				Sys.putEnv("PATH", Sys.getEnv("PATH") + ";" + path);
				if(checkExecutable())
					return;
			}
	}

	override public function updateInCwd(libName:String):Bool
	{
		var doPull = true;

		if(0 != Sys.command(executable, ["diff", "--exit-code"]) || 0 != Sys.command(executable, ["diff", "--cached", "--exit-code"]))
		{
			switch Main.ask("Reset changes to " + libName + " git repo so we can pull latest version?")
			{
				case Answer.Yes:
					Sys.command(executable, ["reset", "--hard"]);
				case Answer.No:
					doPull = false;
					Main.print("Git repo left untouched");
			}
		}
		if(doPull){
			Sys.command("git", ["pull"]);
		}
		return doPull;
	}
}

class Mercurial extends Vcs// implements IVcs
{
	public function new()
	{
		super("hg", "hg", "Mercurial");
	}

	override private function searchExecutable():Void
	{
		super.searchExecutable();

		if(available)
			return;

		// if we have already msys git/cmd in our PATH
		var match = ~/(.*)hg([\\|\/])cmd$/;
		for(path in Sys.getEnv("PATH").split(";"))
		{
			if(match.match(path.toLowerCase()))
			{
				var newPath = match.matched(1) + executable + match.matched(2) + "bin";
				Sys.putEnv("PATH", Sys.getEnv("PATH") + ";" + newPath);
			}
		}
		checkExecutable();
	}

	override public function updateInCwd(libName:String):Bool
	{
		var changed = false;
		cmd(executable, ["pull"]);
		var summary = cmd(executable, ["summary"]).out;
		var diff = cmd(executable, ["diff", "-U", "2", "--git", "--subrepos"]);
		var status = cmd(executable, ["status"]);

		// get new pulled changesets:
		// (and search num of sets)
		summary = summary.substr(0, summary.length - 1);
		summary = summary.substr(summary.lastIndexOf("\n") + 1);
		// we don't know any about locale then taking only Digit-exising:s
		changed = ~/(\d)/.match(summary);
		if(changed)
			// print new pulled changesets:
			Main.print(summary);


		if(diff.code + status.code + diff.out.length + status.out.length != 0)
		{
			Main.print(diff.out);
			switch Main.ask("Reset changes to " + libName + " " + name + " repo so we can update to latest version?")
			{
				case Answer.Yes:
					Sys.command(executable, ["update", "--clean"]);
				case Answer.No:
					changed = false;
					Main.print(name + " repo left untouched");
			}
		}
		else if(changed)
			Sys.command(executable, ["update"]);

		return changed;
	}
}