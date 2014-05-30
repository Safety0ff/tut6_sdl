import std.file : thisExePath;
import std.path : buildPath, dirName;
import std.range : chunks;

import derelict.sdl2.sdl;
import derelict.sdl2.image;
import derelict.opengl3.gl;

import dgl;

import gl3n.linalg;
import gl3n.math;

import glamour.texture;

/// The type of projection we want to use.
enum ProjectionType
{
    perspective,
    orthographic,
}

/**
    Contains all of our OpenGL program state.
    This avoids the use of globals and
    makes the code more maintainable.
*/
struct ProgramState
{
    ///
    this(SDL_Window* window)
    {
        this.window = window;
        this.workDirPath = thisExePath.dirName.buildPath("..");
        this.lastTime = SDL_GetTicks();

        initVertices();
        initUV();
        initTextures();
        initShaders();
        initProgram();
        initAttributesUniforms();
        updateInputControls();
        updateProjection();
        initVao();
        SDL_GetRelativeMouseState(null, null);
    }

    /** Release all OpenGL resources. */
    ~this()
    {
        vertexBuffer.release();
        uvBuffer.release();
        texture.remove();

        foreach (shader; shaders)
            shader.release();

        program.release();
    }

    /// Get the projection type.
    @property ProjectionType projectionType()
    {
        return _projectionType;
    }

    /// Set a new projection type. This will recalculate the mvp matrix.
    @property void projectionType(ProjectionType newProjectionType)
    {
        if (newProjectionType == _projectionType)
            return;

        _projectionType = newProjectionType;
        updateProjection();
    }

    /// Get the current fov.
    @property float fov()
    {
        return _fov;
    }

    /// Set a new fov. This will recalculate the mvp matrix.
    @property void fov(float newFov)
    {
        if (newFov is fov)  // floats are bit-equal (note: don't ever use '==' with floats)
            return;

        _fov = newFov;
        updateProjection();
    }

    /** Update all the game state. */
    void gameTick()
    {
        updateInputControls();
        updateProjection();
    }

    /**
        Recalculate the projection (e.g. after a FOV change or mouse position change).
        Renamed from initProjection from previous tutorials.
    */
    void updateProjection()
    {
        auto projMatrix = getProjMatrix();
        auto viewMatrix = getViewMatrix();
        auto modelMatrix = getModelMatrix();

        // Remember that matrix multiplication is right-to-left.
        this.mvpMatrix = projMatrix * viewMatrix * modelMatrix;
    }

private:

    void initVertices()
    {
        // Our vertices. Three consecutive floats make a vertex (X, Y, Z).
        // cube = 6 squares.
        // square = 2 faces (2 triangles).
        // triangle = 3 vertices.
        // vertex = 3 floats.
        const float[] positions =
        [
            -1.0f, -1.0f, -1.0f,  // triangle #1 begin
            -1.0f, -1.0f,  1.0f,
            -1.0f,  1.0f,  1.0f,  // triangle #1 end
             1.0f,  1.0f, -1.0f,  // triangle #2 begin
            -1.0f, -1.0f, -1.0f,
            -1.0f,  1.0f, -1.0f,  // triangle #2 end
             1.0f, -1.0f,  1.0f,  // etc..
            -1.0f, -1.0f, -1.0f,
             1.0f, -1.0f, -1.0f,
             1.0f,  1.0f, -1.0f,
             1.0f, -1.0f, -1.0f,
            -1.0f, -1.0f, -1.0f,
            -1.0f, -1.0f, -1.0f,
            -1.0f,  1.0f,  1.0f,
            -1.0f,  1.0f, -1.0f,
             1.0f, -1.0f,  1.0f,
            -1.0f, -1.0f,  1.0f,
            -1.0f, -1.0f, -1.0f,
            -1.0f,  1.0f,  1.0f,
            -1.0f, -1.0f,  1.0f,
             1.0f, -1.0f,  1.0f,
             1.0f,  1.0f,  1.0f,
             1.0f, -1.0f, -1.0f,
             1.0f,  1.0f, -1.0f,
             1.0f, -1.0f, -1.0f,
             1.0f,  1.0f,  1.0f,
             1.0f, -1.0f,  1.0f,
             1.0f,  1.0f,  1.0f,
             1.0f,  1.0f, -1.0f,
            -1.0f,  1.0f, -1.0f,
             1.0f,  1.0f,  1.0f,
            -1.0f,  1.0f, -1.0f,
            -1.0f,  1.0f,  1.0f,
             1.0f,  1.0f,  1.0f,
            -1.0f,  1.0f,  1.0f,
             1.0f, -1.0f,  1.0f
        ];

        this.vertexBuffer = new GLBuffer(positions, UsageHint.staticDraw);
    }

    void initUV()
    {
        this.uvBuffer = new GLBuffer(uvArr, UsageHint.staticDraw);
    }

    void initTextures()
    {
        string textPath = workDirPath.buildPath("textures/uvtemplate.png");
        this.texture = Texture2D.from_image(textPath);
    }

    void initShaders()
    {
        enum vertexShader = q{
            #version 330 core

            // Input vertex data, different for all executions of this shader.
            layout(location = 0) in vec3 vertexPosition_modelspace;

            // this is forwarded to the fragment shader.
            layout(location = 1) in vec2 vertexUV;

            // forward
            out vec2 fragmentUV;

            // Values that stay constant for the whole mesh.
            uniform mat4 mvpMatrix;

            void main()
            {
                // Output position of the vertex, in clip space : mvpMatrix * position
                gl_Position = mvpMatrix * vec4(vertexPosition_modelspace, 1);

                // forward to the fragment shader
                fragmentUV = vertexUV;
            }
        };

        enum fragmentShader = q{
            #version 330 core

            // interpolated values from the vertex shader
            in vec2 fragmentUV;

            // output
            out vec3 color;

            // this is our constant texture. It's constant throughout the running of the program,
            // but can be changed between each run.
            uniform sampler2D textureSampler;

            void main()
            {
                // we pick one of the pixels in the texture based on the 2D coordinate value of fragmentUV.
                color = texture(textureSampler, fragmentUV).rgb;
            }
        };

        this.shaders ~= Shader.fromText(ShaderType.vertex, vertexShader);
        this.shaders ~= Shader.fromText(ShaderType.fragment, fragmentShader);
    }

    void initProgram()
    {
        this.program = new Program(shaders);
    }

    void initAttributesUniforms()
    {
        this.positionAttribute = program.getAttribute("vertexPosition_modelspace");
        this.uvAttribute = program.getAttribute("vertexUV");

        this.mvpUniform = program.getUniform("mvpMatrix");
        this.textureSamplerUniform = program.getUniform("textureSampler");
    }

    /**
        Check the keyboard and mouse input state against the last game tick,
        and update the camera position and view direction.
    */
    void updateInputControls()
    {
        // Compute time difference between current and last frame
        double currentTime = SDL_GetTicks();
        float deltaTime = cast(float)(currentTime - lastTime);

        // For the next frame, the "last time" will be "now"
        lastTime = currentTime;

        // Get mouse position
        int xpos, ypos;
        SDL_GetRelativeMouseState(&xpos, &ypos);

        /** If the window loses focus the values can become too large. */
        // not sure if this happens with SDL
        xpos = max(-20, xpos).min(20);
        ypos = max(-20, ypos).min(20);

        // Compute the new orientation
        this.horizontalAngle -= this.mouseSpeed * cast(float)xpos;
        this.verticalAngle   -= this.mouseSpeed * cast(float)ypos;

        // Direction - Spherical coordinates to Cartesian coordinates conversion
        this.direction = vec3(
            cos(this.verticalAngle) * sin(this.horizontalAngle),
            sin(this.verticalAngle),
            cos(this.verticalAngle) * cos(this.horizontalAngle)
        );

        // Right vector
        this.right = vec3(
            sin(this.horizontalAngle - 3.14f / 2.0f), // X
            0,                                        // Y
            cos(this.horizontalAngle - 3.14f / 2.0f)  // Z
        );

        alias KeyForward = SDL_SCANCODE_W;
        alias KeyBackward = SDL_SCANCODE_S;
        alias KeyStrafeLeft = SDL_SCANCODE_A;
        alias KeyStrafeRight = SDL_SCANCODE_D;
        alias KeyClimb = SDL_SCANCODE_SPACE;
        alias KeySink = SDL_SCANCODE_LSHIFT;

        auto kbState = SDL_GetKeyboardState(null);

        if (kbState[KeyForward])
        {
            this.position += deltaTime * this.direction * this.speed;
        }

        if (kbState[KeyBackward])
        {
            this.position -= deltaTime * this.direction * this.speed;
        }

        if (kbState[KeyStrafeLeft])
        {
            this.position -= deltaTime * right * this.speed;
        }

        if (kbState[KeyStrafeRight])
        {
            this.position += deltaTime * right * this.speed;
        }

        if (kbState[KeyClimb])
        {
            this.position.y += deltaTime * this.speed;
        }

        if (kbState[KeySink])
        {
            this.position.y -= deltaTime * this.speed;
        }

        void updateUVBuffer(vec2 offset)
        {
            foreach (ref uv; this.uvArr.chunks(2))
            {
                uv[0] += offset.x;
                uv[1] += offset.y;
            }

            this.uvBuffer.overwrite(this.uvArr);
        }

        if (kbState[SDL_SCANCODE_LEFT])
        {
            updateUVBuffer(vec2(deltaTime * -0.3, 0));
        }

        if (kbState[SDL_SCANCODE_RIGHT])
        {
            updateUVBuffer(vec2(deltaTime * 0.3, 0));
        }

        if (kbState[SDL_SCANCODE_UP])
        {
            updateUVBuffer(vec2(0, deltaTime * 0.3));
        }

        if (kbState[SDL_SCANCODE_DOWN])
        {
            updateUVBuffer(vec2(0, deltaTime * -0.3));
        }
    }

    mat4 getProjMatrix()
    {
        final switch (_projectionType) with (ProjectionType)
        {
            case orthographic:
            {
                float left = -10.0;
                float right = 10.0;
                float bottom = -10.0;
                float top = 10.0;
                float near = 0.0;
                float far = 100.0;
                return mat4.orthographic(left, right, bottom, top, near, far);
            }

            case perspective:
            {
                float near = 0.1f;
                float far = 100.0f;

                int width;
                int height;
                SDL_GetWindowSize(window, &width, &height);
                return mat4.perspective(width, height, _fov, near, far);
            }
        }
    }

    // the view (camera) matrix
    mat4 getViewMatrix()
    {
        // Up vector
        vec3 up = cross(this.right, this.direction);

        return mat4.look_at(
            position,              // Camera is here
            position + direction,  // and looks here
            up                     //
        );
    }

    //
    mat4 getModelMatrix()
    {
        // an identity matrix - the model will be at the origin.
        return mat4.identity();
    }

    void initVao()
    {
        // Note: this must be called when using the core profile,
        // and it must be called before any other OpenGL call.
        // VAOs have a proper use-case but it's not shown here,
        // search the web for VAO documentation and check it out.
        GLuint vao;
        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
    }

    // Our UV coolrdinates.
    // We keep this as an instance member because we're allowing
    // modifications with a keyboard callback, which will re-copy
    // the modified array into the GL buffer.
    // This isn't efficient but it serves as an example.
    float[] uvArr =
    [
        // Note: the '1.0f -' part is there in case the image
        // was already flipped. The texture loading routines in
        // glamour may or may not flip the image vertically,
        // based on the code path it takes.
        0.000059f, 1.0f - 0.000004f,
        0.000103f, 1.0f - 0.336048f,
        0.335973f, 1.0f - 0.335903f,
        1.000023f, 1.0f - 0.000013f,
        0.667979f, 1.0f - 0.335851f,
        0.999958f, 1.0f - 0.336064f,
        0.667979f, 1.0f - 0.335851f,
        0.336024f, 1.0f - 0.671877f,
        0.667969f, 1.0f - 0.671889f,
        1.000023f, 1.0f - 0.000013f,
        0.668104f, 1.0f - 0.000013f,
        0.667979f, 1.0f - 0.335851f,
        0.000059f, 1.0f - 0.000004f,
        0.335973f, 1.0f - 0.335903f,
        0.336098f, 1.0f - 0.000071f,
        0.667979f, 1.0f - 0.335851f,
        0.335973f, 1.0f - 0.335903f,
        0.336024f, 1.0f - 0.671877f,
        1.000004f, 1.0f - 0.671847f,
        0.999958f, 1.0f - 0.336064f,
        0.667979f, 1.0f - 0.335851f,
        0.668104f, 1.0f - 0.000013f,
        0.335973f, 1.0f - 0.335903f,
        0.667979f, 1.0f - 0.335851f,
        0.335973f, 1.0f - 0.335903f,
        0.668104f, 1.0f - 0.000013f,
        0.336098f, 1.0f - 0.000071f,
        0.000103f, 1.0f - 0.336048f,
        0.000004f, 1.0f - 0.671870f,
        0.336024f, 1.0f - 0.671877f,
        0.000103f, 1.0f - 0.336048f,
        0.336024f, 1.0f - 0.671877f,
        0.335973f, 1.0f - 0.335903f,
        0.667969f, 1.0f - 0.671889f,
        1.000004f, 1.0f - 0.671847f,
        0.667979f, 1.0f - 0.335851f
    ];

    // time since the last game tick
    double lastTime = 0;

    // camera position
    vec3 position = vec3(0, 0, 5);

    // camera direction
    vec3 direction;

    vec3 right;

    // Initial horizontal angle : toward -Z
    float horizontalAngle = 3.14f;

    // Initial vertical angle : none
    float verticalAngle = 0.0f;

    // Initial Field of View
    float initialFoV = 45.0f;

    float speed      = 3.0f; // 3 units / second
    float mouseSpeed = 0.003f;

    // We need the window size to calculate the projection matrix.
    SDL_Window* window;

    // Selectable projection type.
    ProjectionType _projectionType = ProjectionType.perspective;

    // Field of view (note that this was hardcoded in getProjMatrix in previous tutorials)
    float _fov = 45.0;

    // reference to a GPU buffer containing the vertices.
    GLBuffer vertexBuffer;

    // ditto, but containing UV coordinates.
    GLBuffer uvBuffer;

    // the texture we're going to use for the cube.
    Texture2D texture;

    // kept around for cleanup.
    Shader[] shaders;

    // our main GL program.
    Program program;

    // The vertex positions attribute
    Attribute positionAttribute;

    // ditto for the UV coordinates.
    Attribute uvAttribute;

    // The uniform (location) of the matrix in the shader.
    Uniform mvpUniform;

    // Ditto for the texture sampler.
    Uniform textureSamplerUniform;

    // The currently calculated matrix.
    mat4 mvpMatrix;

private:
    // root path where the 'textures' and 'bin' folders can be found.
    const string workDirPath;
}

/** Our main render routine. */
void render(ref ProgramState state)
{
    glClearColor(0.0f, 0.0f, 0.4f, 0.0f);  // dark blue
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    state.program.bind();

    // set this to true when converting matrices from row-major order
    // to column-major order. Note that gl3n uses row-major ordering,
    // unlike the C++ glm library.
    enum doTranspose = GL_TRUE;
    enum matrixCount = 1;
    glUniformMatrix4fv(state.mvpUniform.ID, matrixCount, doTranspose, &state.mvpMatrix[0][0]);

    bindTexture(state);
    bindPositionAttribute(state);
    bindUVAttribute(state);

    enum startIndex = 0;

    // cube = 6 squares.
    // square = 2 faces (2 triangles).
    // triangle = 3 vertices.
    enum vertexCount = 6 * 2 * 3;
    glDrawArrays(GL_TRIANGLES, startIndex, vertexCount);

    state.texture.unbind();

    state.positionAttribute.disable();
    state.vertexBuffer.unbind();

    state.uvAttribute.disable();
    state.uvBuffer.unbind();

    state.program.unbind();
}

void bindPositionAttribute(ref ProgramState state)
{
    enum int size = 3;  // (x, y, z) per vertex
    enum GLenum type = GL_FLOAT;
    enum bool normalized = false;
    enum int stride = 0;
    enum int offset = 0;

    state.vertexBuffer.bind(state.positionAttribute, size, type, normalized, stride, offset);
    state.positionAttribute.enable();
}

void bindUVAttribute(ref ProgramState state)
{
    // (u, v) per vertex
    enum int size = 2;
    enum GLenum type = GL_FLOAT;
    enum bool normalized = false;
    enum int stride = 0;
    enum int offset = 0;

    state.uvBuffer.bind(state.uvAttribute, size, type, normalized, stride, offset);
    state.uvAttribute.enable();
}

void bindTexture(ref ProgramState state)
{
    // set our texture sampler to use Texture Unit 0
    enum textureUnit = 0;
    state.program.setUniform1i(state.textureSamplerUniform, textureUnit);

    state.texture.activate();
    state.texture.bind();
}
