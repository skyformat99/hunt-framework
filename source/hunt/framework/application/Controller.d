/*
 * Hunt - A high-level D Programming Language Web framework that encourages rapid development and clean, pragmatic design.
 *
 * Copyright (C) 2015-2019, HuntLabs
 *
 * Website: https://www.huntlabs.net/
 *
 * Licensed under the Apache-2.0 License.
 *
 */

module hunt.framework.application.Controller;

import hunt.logging.ConsoleLogger;

public import hunt.framework.http.Response;
public import hunt.framework.http.Request;
public import hunt.framework.application.MiddlewareInterface;

import hunt.http.server;
import hunt.http.routing;
import hunt.cache;
import hunt.framework.Simplify;
import hunt.framework.view;
import hunt.validation;
import hunt.framework.http.Form;

import std.exception;
import std.traits;

enum Action;

alias Request = HttpServerRequest;
alias Response = HttpServerResponse;

/**
 * 
 */
abstract class Controller
{
    // private OutputStream _outputStream;
    

    protected
    {
        RoutingContext _routingContext;
        Response _response;
        View _view;
        ///called before all actions
        MiddlewareInterface[string] middlewares;
    }

    @property View view()
    {
        if (_view is null)
        {
            _view = GetViewObject();
            // TODO: Tasks pending completion -@zhangxueping at 2020-01-02T18:16:11+08:00
            // 
            // _view.setRouteGroup(this.request.route.getGroup());
            // _view.setLocale(this.request.locale());
        }

        return _view;
    }

    Request request() {
        return _routingContext.getRequest();
    }

    final @property Response response()
    {
        return _routingContext.getResponse();
    }

    /// called before action  return true is continue false is finish
    bool before()
    {
        return true;
    }

    /// called after action  return true is continue false is finish
    bool after()
    {
        return true;
    }

    ///add middleware
    ///return true is ok, the named middleware is already exist return false
    bool addMiddleware(MiddlewareInterface m)
    {
        if(m is null || this.middlewares.get(m.name(), null) !is null)
        {
            return false;
        }

        this.middlewares[m.name()]= m;
        return true;
    }

    // get all middleware
    MiddlewareInterface[string] getMiddlewares()
    {
        return this.middlewares;
    }

    Cache cache()
    {
        return app().cache();
    }
    
    protected final Response doMiddleware()
    {
        version (HUNT_DEBUG) logDebug("doMiddlware ..");

        // TODO: Tasks pending completion -@zhangxueping at 2020-01-02T18:24:39+08:00
        // 

        foreach (m; middlewares)
        {
            version (HUNT_DEBUG) logDebugf("do %s onProcess ..", m.name());

            auto response = m.onProcess(this.request, this.response);
            if (response is null)
            {
                continue;
            }

            version (HUNT_DEBUG) logDebugf("Middleware %s is to retrun.", m.name);
            return response;
        }

        return null;
    }

    @property bool isAsync()
    {
        return true;
    }

    string processGetNumericString(string value)
    {
        import std.string;

        if (!isNumeric(value))
        {
            return "0";
        }

        return value;
    }

    Response processResponse(Response res)
    {
        // TODO: Tasks pending completion -@zhangxueping at 2020-01-06T14:01:43+08:00
        // 
        // have ResponseHandler binding?
        // if (res.httpResponse() is null)
        // {
        //     res.setHttpResponse(request.responseHandler());
        // }

        return res;
    }

    void dispose() {
        version(HUNT_HTTP_DEBUG) trace("Do nothing");
    }
}

mixin template MakeController(string moduleName = __MODULE__)
{
    mixin HuntDynamicCallFun!(typeof(this), moduleName);
}

mixin template HuntDynamicCallFun(T, string moduleName) if(is(T : Controller))
{
public:
    enum allActions = __createCallActionMethod!(T, moduleName);
    // version (HUNT_DEBUG) 
    pragma(msg, allActions);

    mixin(allActions);
    
    shared static this()
    {
        enum routemap = __createRouteMap!(T, moduleName);
        // pragma(msg, routemap);
        mixin(routemap);
    }
}

private
{
    enum actionName = "Action";
    enum actionNameLength = actionName.length;

    bool isActionMember(string name)
    {
        return name.length > actionNameLength && name[$ - actionNameLength .. $] == actionName;
    }
}

string __createCallActionMethod(T, string moduleName)()
{
    import std.traits;
    import std.format;
    import std.string;
    import std.conv;
    
    import hunt.logging.ConsoleLogger;

    string str = `

        import hunt.http.server.HttpServerRequest;
        import hunt.http.server.HttpServerResponse;
        import hunt.http.routing.RoutingContext;
        import hunt.http.HttpBody;

        void callActionMethod(string methodName, RoutingContext context) {
            _routingContext = context;
            Response actionResponse=null;
            HttpBody rb;
            version (HUNT_FM_DEBUG) logDebug("methodName=", methodName);
            import std.conv;

            switch(methodName){
    `;

    foreach (memberName; __traits(allMembers, T))
    {
        // TODO: Tasks pending completion -@zhangxueping at 2019-09-24T11:47:45+08:00
        // Can't detect the error: void test(error);
        // pragma(msg, "memberName: ", memberName);
        static if (is(typeof(__traits(getMember, T, memberName)) == function))
        {
            // pragma(msg, "got: ", memberName);

            enum _isActionMember = isActionMember(memberName);
            foreach (t; __traits(getOverloads, T, memberName))
            {
                // alias RT = ReturnType!(t);

                //alias pars = ParameterTypeTuple!(t);
                static if (hasUDA!(t, Action) || _isActionMember)
                {
                    str ~= "\t\tcase \"" ~ memberName ~ "\": {\n";

                    static if (hasUDA!(t, Action) || _isActionMember)
                    {
                        //before
                        str ~= q{
                            if(this.getMiddlewares().length) {
                                auto response = this.doMiddleware();

                                if (response !is null) {
                                    // return response;
                                    _routingContext.response = response;
                                    return;
                                }
                            }

                            if (!this.before()) {
                                _routingContext.response = response;
                                return;
                            }
                        };
                    }

                    // Action parameters
                    auto params = ParameterIdentifierTuple!t;
                    string paramString = "";

                    static if (params.length > 0)
                    {
                        import std.conv : to;

                        string varName = "";
                        alias paramsType = Parameters!t;

                        static foreach (int i; 0..params.length)
                        {
                            varName = "var" ~ i.to!string;

                            static if (paramsType[i].stringof == "string")
                            {
                                str ~= "\t\tstring " ~ varName ~ " = request.get(\"" ~ params[i] ~ "\");\n";
                            }
                            else
                            {
                                static if (isNumeric!(paramsType[i])) {
                                    str ~= "\t\tauto " ~ varName ~ " = this.processGetNumericString(request.get(\"" ~ 
                                        params[i] ~ "\")).to!" ~ paramsType[i].stringof ~ ";\n";
                                } else static if(is(paramsType[i] : Form)) {
                                    str ~= "\t\tauto " ~ varName ~ " = request.bindForm!" ~ paramsType[i].stringof ~ "();\n";
                                } else {
                                    str ~= "\t\tauto " ~ varName ~ " = request.get(\"" ~ params[i] ~ "\").to!" ~ 
                                            paramsType[i].stringof ~ ";\n";
                                }
                            }

                            paramString ~= i == 0 ? varName : ", " ~ varName;

                            varName = "";
                        }
                    }

                    // call Action
                    static if (is(ReturnType!t == void)) {
                        str ~= "\t\tthis." ~ memberName ~ "(" ~ paramString ~ ");\n";
                    } else {
                        str ~= "\t\t" ~ ReturnType!t.stringof ~ " result = this." ~ 
                                memberName ~ "(" ~ paramString ~ ");\n";

                        static if (is(ReturnType!t : Response))
                        {
                            str ~= "\t\t_routingContext.response = result;\n";
                        }
                        else
                        {
                            // str ~= "\t\tactionResponse = this.response;\n";

                            str ~="\t\trb = HttpBody.create(result);
                            this.response.setBody(rb);\n";
                        }
                    }

                    // str ~= "\t\tactionResponse = this.processResponse(actionResponse);\n";

                    static if(hasUDA!(t, Action) || _isActionMember)
                    {
                        str ~= "\t\tthis.after();\n";
                    }
                    str ~= "\n\t\tbreak;\n\t}\n";
                }
            }
        }
    }

    str ~= "\tdefault:\n\tbreak;\n\t}\n\n";
    // str ~= "\t _routingContext.response = actionResponse;\n";
    // str ~= "\treturn actionResponse;\n";
    str ~= "}";

    return str;
}

string __createRouteMap(T, string moduleName)()
{
    string str = "";

    // pragma(msg, "moduleName: ", moduleName);

    // str ~= q{
    //     import hunt.framework.application.StaticfileController;
    //     registerRouteHandler("hunt.application.staticfile.StaticfileController.doStaticFile", 
    //         &callHandler!(StaticfileController, "doStaticFile"));
    // };

    enum len = "Controller".length;
    string controllerName = moduleName[0..$-len];

    foreach (memberName; __traits(allMembers, T))
    {
        // pragma(msg, "memberName: ", memberName);

        static if (is(typeof(__traits(getMember, T, memberName)) == function))
        {
            foreach (t; __traits(getOverloads, T, memberName))
            {
                static if ( /*ParameterTypeTuple!(t).length == 0 && */ hasUDA!(t, Action))
                {
                    str ~= "\n\tregisterRouteHandler(\"" ~ controllerName ~ "." ~ T.stringof ~ "." ~ memberName
                        ~ "\", (context) { 
                            callHandler!(" ~ T.stringof ~ ",\"" ~ memberName ~ "\")(context);
                    });\n";
                }
                else static if (isActionMember(memberName))
                {
                    enum strippedMemberName = memberName[0 .. $ - actionNameLength];
                    str ~= "\n\tregisterRouteHandler(\"" ~ controllerName ~ "." ~ T.stringof ~ "." ~ strippedMemberName
                        ~ "\", (context) { 
                            callHandler!(" ~ T.stringof ~ ",\"" ~ memberName ~ "\")(context);
                    });\n";
                }
            }
        }
    }

    return str;
}

void callHandler(T, string method)(RoutingContext context)
        if (is(T == class) || (is(T == struct) && hasMember!(T, "__CALLACTION__")))
{
    T controller = new T();
    import core.memory;
    scope(exit) {
        // TODO: Tasks pending completion -@zhangxueping at 2020-01-08T11:43:51+08:00
        // 
    // str ~= "\timport hunt.framework.Simplify;\n";
    // str ~= "\tcloseDefaultEntityManager();\n";
        controller.dispose();
        if(!controller.isAsync){controller.destroy(); GC.free(cast(void *)controller);}
    }

    // req.action = method;
    // auto req = context.getRequest();
    controller.callActionMethod(method, context);

    context.end();
}

RoutingHandler getRouteHandler(string str)
{
    // if (!_init)
    //     _init = true;
    return _actions.get(str, null);
}

void registerRouteHandler(string str, RoutingHandler method)
{
    version (HUNT_DEBUG) logDebug("add route handler: ", str);
    // if (!_init)
    {
        import std.string : toLower;
        _actions[str.toLower] = method;
    }
}

private:
// __gshared bool _init = false;
__gshared RoutingHandler[string] _actions;
