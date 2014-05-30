import core.time;
import core.sync.mutex;

import std.stdio;
import std.container;
import std.concurrency;

import derelict.sdl2.sdl;
import derelict.sdl2.types;
import derelict.sdl2.image;
import derelict.opengl3.gl;
import derelictsdl2_ext;

import sdl_ext;

import tut6;

// TODO: replace this mess with actual architecture.
__gshared SDL_Window* window;
__gshared DList!(void delegate()) eventThreadJobs;
__gshared Mutex jobmutex;
__gshared DList!(SDL_Event) inputEvents;
__gshared Mutex eventmutex;

enum ThreadState
{
    Init,
    Run,
    Cleanup,
    Terminate
}

int main() {

    ThreadState state = ThreadState.Init;

    // Load the SDL 2 library.
    DerelictSDL2.load();
    DerelictSDL2EXT.load();
    DerelictGL3.load();
    DerelictSDL2Image.load();

    if (SDL_Init(SDL_INIT_VIDEO|SDL_INIT_TIMER) < 0)
        return 1;

    jobmutex = new Mutex;
    eventmutex = new Mutex;

    auto tid = spawn(&realmain, thisTid);

    while (state == ThreadState.Init)
    {
        jobmutex.lock();
        foreach (ref job; eventThreadJobs)
            job();
        eventThreadJobs.clear();
        jobmutex.unlock();
        receiveTimeout(dur!"msecs"(4), (ThreadState newState) { state = newState; });
    }
    SDL_Event ev;
eventLoop:
    while (state == ThreadState.Run)
    {
        EXT_WaitEvent(window, 4);
        while (SDL_PollEvent(&ev))
        {
            if (ev.type == SDL_QUIT
                || ev.type == SDL_KEYUP && ev.key.keysym.sym == SDLK_ESCAPE)
            {
                state = ThreadState.Cleanup;
                send(tid, state);
                break eventLoop;
            }
            else
            {
                eventmutex.lock();
                inputEvents.insertBack(ev);
                eventmutex.unlock();
            }
        }
        jobmutex.lock();
        foreach (ref job; eventThreadJobs)
            job();
        eventThreadJobs.clear();
        jobmutex.unlock();
        receiveTimeout(dur!"nsecs"(0), (ThreadState newState) { state=newState; });
    }

    while (state == ThreadState.Cleanup)
    {
        jobmutex.lock();
        foreach (ref job; eventThreadJobs)
            job();
        eventThreadJobs.clear();
        jobmutex.unlock();
        receiveTimeout(dur!"msecs"(4), (ThreadState newState) { state=newState; });
    }

    SDL_Quit();
    return 0;
}

void realmain(Tid tid)
{
    scope(exit) send(tid, ThreadState.Terminate);

    import core.sync.semaphore;
    Semaphore sem = new Semaphore;
    jobmutex.lock();
    eventThreadJobs.insertBack(()
    {
        window = SDL_CreateWindow("Tutorial 06 - Keyboard & Mouse",
                    SDL_WINDOWPOS_UNDEFINED,
                    SDL_WINDOWPOS_UNDEFINED,
                    1024,700,
                    SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);
        sem.notify();
        SDL_SetRelativeMouseMode(SDL_TRUE); // enable trapping/warping
    });
    jobmutex.unlock();
    sem.wait();

    scope(exit)
    {
        jobmutex.lock();
        eventThreadJobs.insertBack(()
        {
            SDL_DestroyWindow(window);
            window = null;
            sem.notify();
        });
        jobmutex.unlock();
        sem.wait();
    }

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
    SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 4);
    SDL_GLContext glContext = SDL_GL_CreateContext(window);
    if (glContext is null)
    {
        stderr.writeln("There was an error creating an OpenGL 3.3 context!");
        send(tid, ThreadState.Cleanup);
        return;
    }

    scope(exit)
    {
        jobmutex.lock();
        eventThreadJobs.insertBack(()
        {
            SDL_GL_DeleteContext(glContext);
            sem.notify();
        });
        jobmutex.unlock();
        sem.wait();
    }
    DerelictGL3.reload();
    import dgl.loader : loadGL;
    loadGL();

    send(tid, ThreadState.Run); // signal initialisation done

    SDL_GL_MakeCurrent(window, glContext);
    SDL_GL_SetSwapInterval(1);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glEnable(GL_CULL_FACE);

    auto state = ProgramState(window);

    bool shutdown;
    while(!shutdown)
    {
        eventmutex.lock();
        auto events = inputEvents[];
        inputEvents.remove(events); // N.B. doesn't invalidate 'events'.
        eventmutex.unlock();
        if (!events.empty)
        {
            writeln("Frame time: ", SDL_GetTicks());
            foreach (event; events)
                writeln("\t ", event.common.timestamp);
        }
        state.gameTick();
        render(state);
        SDL_GL_SwapWindow(window);
        receiveTimeout(dur!"nsecs"(0), (ThreadState newState) { if (newState != ThreadState.Run) shutdown = true; });
    }
}