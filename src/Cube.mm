// main.cpp: initialisation & main loop

#import <ObjFW/ObjFW.h>

#include "cube.h"

@interface Cube: OFObject <OFApplicationDelegate>
@end

OF_APPLICATION_DELEGATE(Cube)

void cleanup(char *msg)         // single program exit point;
{
	SDL_ShowCursor(1);

	if (msg) {
#ifdef WIN32
		MessageBox(NULL, msg, "cube fatal error", MB_OK|MB_SYSTEMMODAL);
#else
		printf(msg);
#endif
	}

	SDL_Quit();
};

void quit()                     // normal exit
{
	writeservercfg();
	cleanup(NULL);
	[OFApplication terminate];
};

void fatal(char *s, char *o)    // failure exit
{
	sprintf_sd(msg)("%s%s (%s)\n", s, o, SDL_GetError());
	cleanup(msg);
	[OFApplication terminateWithStatus: 1];
};

void *alloc(int s)              // for some big chunks... most other allocs use the memory pool
{
    void *b = calloc(1,s);
    if(!b) fatal("out of memory!");
    return b;
};

int scr_w = 640;
int scr_h = 480;

void screenshot()
{
    SDL_Surface *image;
    SDL_Surface *temp;
    int idx;
    if(image = SDL_CreateRGBSurface(SDL_SWSURFACE, scr_w, scr_h, 24, 0x0000FF, 0x00FF00, 0xFF0000, 0))
    {
        if(temp  = SDL_CreateRGBSurface(SDL_SWSURFACE, scr_w, scr_h, 24, 0x0000FF, 0x00FF00, 0xFF0000, 0))
        {
            glReadPixels(0, 0, scr_w, scr_h, GL_RGB, GL_UNSIGNED_BYTE, image->pixels);
            for (idx = 0; idx<scr_h; idx++)
            {
                char *dest = (char *)temp->pixels+3*scr_w*idx;
                memcpy(dest, (char *)image->pixels+3*scr_w*(scr_h-1-idx), 3*scr_w);
                endianswap(dest, 3, scr_w);
            };
            sprintf_sd(buf)("screenshots/screenshot_%d.bmp", lastmillis);
            SDL_SaveBMP(temp, path(buf));
            SDL_FreeSurface(temp);
        };
        SDL_FreeSurface(image);
    };
};

COMMAND(screenshot, ARG_NONE);
COMMAND(quit, ARG_NONE);

void keyrepeat(bool on)
{
    SDL_EnableKeyRepeat(on ? SDL_DEFAULT_REPEAT_DELAY : 0,
                             SDL_DEFAULT_REPEAT_INTERVAL);
};

VARF(gamespeed, 10, 100, 1000, if(multiplayer()) gamespeed = 100);
VARP(minmillis, 0, 5, 1000);

int islittleendian = 1;
int framesinmap = 0;

@implementation Cube
- (void)applicationDidFinishLaunching
{
	OFAutoreleasePool *pool = [OFAutoreleasePool new];
	OFArray *arguments = [OFApplication arguments];

    bool dedicated = false;
    int fs = SDL_FULLSCREEN, par = 0, uprate = 0, maxcl = 4;
    char *sdesc = "", *ip = "", *master = NULL, *passwd = "";
    islittleendian = *((char *)&islittleendian);

    #define log(s) conoutf("init: %s", s)
    log("sdl");

	for (OFString *arg in arguments) {
		OFString *a = [arg substringWithRange:
		    of_range(2, arg.length - 2)];

		if ([arg isEqual: @"-d"])
			dedicated = true;
		else if ([arg isEqual: @"-t"])
			fs = 0;
		else if ([arg hasPrefix: @"-w"])
			scr_w = [a decimalValue];
		else if ([arg hasPrefix: @"-h"])
			scr_h = [a decimalValue];
		else if ([arg hasPrefix: @"-u"])
			uprate = [a decimalValue];
		else if ([arg hasPrefix: @"-n"])
			sdesc = strdup([a UTF8String]);
		else if ([arg hasPrefix: @"-i"])
			ip = strdup([a UTF8String]);
		else if ([arg hasPrefix: @"-m"])
			master = strdup([a UTF8String]);
		else if ([arg hasPrefix: @"-p"])
			passwd = strdup([a UTF8String]);
		else if ([arg hasPrefix: @"-c"])
			maxcl = [a decimalValue];
		else if ([arg hasPrefix: @"-"])
			conoutf("unknown commandline option");
		else conoutf("unknown commandline argument");
	}

	[pool release];

    #ifdef _DEBUG
    par = SDL_INIT_NOPARACHUTE;
    fs = 0;
    #endif

    if(SDL_Init(SDL_INIT_TIMER|SDL_INIT_VIDEO|par)<0) fatal("Unable to initialize SDL");

    log("net");
    if(enet_initialize()<0) fatal("Unable to initialise network module");

    initclient();
    initserver(dedicated, uprate, sdesc, ip, master, passwd, maxcl);  // never returns if dedicated

    log("world");
    empty_world(7, true);

    log("video: sdl");
    if(SDL_InitSubSystem(SDL_INIT_VIDEO)<0) fatal("Unable to initialize SDL Video");

    log("video: mode");
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    if(SDL_SetVideoMode(scr_w, scr_h, 0, SDL_OPENGL|fs)==NULL) fatal("Unable to create OpenGL screen");

    log("video: misc");
    SDL_WM_SetCaption("cube engine", NULL);
    SDL_WM_GrabInput(SDL_GRAB_ON);
    keyrepeat(false);
    SDL_ShowCursor(0);

    log("gl");
    gl_init(scr_w, scr_h);

    log("basetex");
    int xs, ys;
    if(!installtex(2,  path(newstring("data/newchars.png")), xs, ys) ||
       !installtex(3,  path(newstring("data/martin/base.png")), xs, ys) ||
       !installtex(6,  path(newstring("data/martin/ball1.png")), xs, ys) ||
       !installtex(7,  path(newstring("data/martin/smoke.png")), xs, ys) ||
       !installtex(8,  path(newstring("data/martin/ball2.png")), xs, ys) ||
       !installtex(9,  path(newstring("data/martin/ball3.png")), xs, ys) ||
       !installtex(4,  path(newstring("data/explosion.jpg")), xs, ys) ||
       !installtex(5,  path(newstring("data/items.png")), xs, ys) ||
       !installtex(1,  path(newstring("data/crosshair.png")), xs, ys)) fatal("could not find core textures (hint: run cube from the parent of the bin directory)");

    log("sound");
    initsound();

    log("cfg");
    newmenu("frags\tpj\tping\tteam\tname");
    newmenu("ping\tplr\tserver");
    exec("data/keymap.cfg");
    exec("data/menus.cfg");
    exec("data/prefabs.cfg");
    exec("data/sounds.cfg");
    exec("servers.cfg");
    if(!execfile("config.cfg")) execfile("data/defaults.cfg");
    exec("autoexec.cfg");

    log("localconnect");
    localconnect();
    changemap("metl3");		// if this map is changed, also change depthcorrect()

    log("mainloop");
    int ignore = 5;
    for(;;)
    {
        int millis = SDL_GetTicks()*gamespeed/100;
        if(millis-lastmillis>200) lastmillis = millis-200;
        else if(millis-lastmillis<1) lastmillis = millis-1;
        if(millis-lastmillis<minmillis) SDL_Delay(minmillis-(millis-lastmillis));
        cleardlights();
        updateworld(millis);
        if(!demoplayback) serverslice((int)time(NULL), 0);
        static float fps = 30.0f;
        fps = (1000.0f/curtime+fps*50)/51;
        computeraytable(player1->o.x, player1->o.y);
        readdepth(scr_w, scr_h);
        SDL_GL_SwapBuffers();
        extern void updatevol(); updatevol();
        if(framesinmap++<5)	// cheap hack to get rid of initial sparklies, even when triple buffering etc.
        {
			player1->yaw += 5;
			gl_drawframe(scr_w, scr_h, fps);
			player1->yaw -= 5;
        };
        gl_drawframe(scr_w, scr_h, fps);
        SDL_Event event;
        int lasttype = 0, lastbut = 0;
        while(SDL_PollEvent(&event))
        {
            switch(event.type)
            {
                case SDL_QUIT:
                    quit();
                    break;

                case SDL_KEYDOWN:
                case SDL_KEYUP:
                    keypress(event.key.keysym.sym, event.key.state==SDL_PRESSED, event.key.keysym.unicode);
                    break;

                case SDL_MOUSEMOTION:
                    if(ignore) { ignore--; break; };
                    mousemove(event.motion.xrel, event.motion.yrel);
                    break;

                case SDL_MOUSEBUTTONDOWN:
                case SDL_MOUSEBUTTONUP:
                    if(lasttype==event.type && lastbut==event.button.button) break; // why?? get event twice without it
                    keypress(-event.button.button, event.button.state!=0, 0);
                    lasttype = event.type;
                    lastbut = event.button.button;
                    break;
            };
        };
    };
    quit();
    [OFApplication terminateWithStatus: 1];
}

- (void)applicationWillTerminate
{
	stop();
	disconnect(true);
	writecfg();
	cleangl();
	cleansound();
	cleanupserver();
	SDL_ShowCursor(1);
}
@end