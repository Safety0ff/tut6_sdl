import core.time;
import core.sync.mutex;

import std.stdio;
import std.container;
import std.concurrency;

import derelict.sdl2.sdl;
import derelict.sdl2.types;
import derelict.sdl2.image;
import derelict.opengl3.gl;

import tut6;

int main() {

    // Load the SDL 2 library.
    DerelictSDL2.load();
    DerelictGL3.load();
    DerelictSDL2Image.load();

    if (SDL_Init(SDL_INIT_VIDEO|SDL_INIT_TIMER) < 0)
        return 1;

    auto window = SDL_CreateWindow("Tutorial 06 - Keyboard & Mouse",
            SDL_WINDOWPOS_UNDEFINED,
            SDL_WINDOWPOS_UNDEFINED,
            1024,700,
            SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);
    scope(exit)    SDL_DestroyWindow(window);

    SDL_SetRelativeMouseMode(SDL_TRUE); // enable trapping/warping

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
    SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 4);
    SDL_GLContext glContext = SDL_GL_CreateContext(window);
    if (glContext is null)
    {
        stderr.writeln("There was an error creating an OpenGL 3.3 context!");
        return 1;
    }
    scope(exit)        SDL_GL_DeleteContext(glContext);

    DerelictGL3.reload();
    import dgl.loader : loadGL;
    loadGL();

    SDL_GL_MakeCurrent(window, glContext);

    SDL_GL_SetSwapInterval(1);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glEnable(GL_CULL_FACE);

    auto state = ProgramState(window);

    SDL_Event ev;
eventLoop:
    bool shutdown;
    while(!shutdown)
    {
        bool firstEv = true;
        while (SDL_PollEvent(&ev))
        {
            if (ev.type == SDL_QUIT
                || ev.type == SDL_KEYUP && ev.key.keysym.sym == SDLK_ESCAPE)
                shutdown = true;
            if (firstEv)
            {
                writeln("Frame time: ", SDL_GetTicks());
                firstEv = false;
            }
            writeln("\t ", ev.common.timestamp);
        }
        state.gameTick();
        render(state);
        SDL_GL_SwapWindow(window);
    }

    SDL_Quit();
    return 0;
}
