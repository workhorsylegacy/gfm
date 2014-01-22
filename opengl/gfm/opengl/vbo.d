module gfm.opengl.vbo;


// Describing vertex, submitting geometry.
// Implement so called Vertex Arrays and VBO (which are Vertex Arrays + OpenGL buffers)

import std.string;

import derelict.opengl3.gl3,
       derelict.opengl3.deprecatedFunctions,
       derelict.opengl3.deprecatedConstants;

import gfm.core.log,
       gfm.opengl.opengl,
       gfm.opengl.program,
       gfm.opengl.buffer;

/**
 * A VertexSpecification makes it easy to use Vertex Buffer Object with interleaved attributes.
 * It's role is similar to the OpenGL VAO one.
 * If the user requests it, the VertexSpecification can "take control" of a given VBO and/or IBO
 * and automatically bind/unbind them when the VertexSpecification is used/unused.
 * You have to specify every attribute manually for now.
 *
 * TODO: Extract vertex specification from a struct at compile-time.
 */
class VertexSpecification
{
    public
    {
        /// Creates a vertex specification.
        this(OpenGL gl)
        {
            _vbo = null;
            _ibo = null;
            _gl = gl;
            _currentOffset = 0;
            _attributes = [];
            _state = State.UNUSED;
        }

        ~this()
        {
            assert(_state == State.UNUSED);
        }

        /// Use this vertex specification.
        /// Throws: $(D OpenGLException) on error.
        void use(GLProgram program = null)
        {
            assert(_state == State.UNUSED);
            if (_vbo !is null) // if we are "in control" of this VBO, we have to bind it to current OpenGL state
                _vbo.bind();
            if (_ibo !is null)  // ditto, for the ibo
                _ibo.bind();
            // for every attribute
            for (uint i = 0; i < _attributes.length; ++i)
                _attributes[i].use(_gl, program, cast(GLsizei) _currentOffset);
            _state = State.USED;
        }

        /// Unuse this vertex specification.
        /// Throws: $(D OpenGLException) on error.
        void unuse()
        {
            assert(_state == State.USED);
            // Leaving a clean state after unusing an object
            // seems the most reasonable way of doing things.
            if (_vbo !is null) // if we are "in control" of this VBO, we have to bind it to current OpenDL state
                _vbo.unbind();
            if (_ibo !is null)  // ditto, for the ibo
                _ibo.unbind();
            // unuse all the attributes
            for (uint i = 0; i < _attributes.length; ++i)
                _attributes[i].unuse(_gl);
            _state = State.UNUSED;
        }

        /// This property allows the user to set/unset the VBO "ownership"
        @property GLBuffer VBO() { return _vbo; } // property can always be read
        /// Ditto
        @property GLBuffer VBO(GLBuffer vbo) { // write property
            assert (_state == State.UNUSED); // Can be modified ONLY when unused
            return _vbo = vbo;
        }

        /// This property allows the user to set/unset the IBO "ownership"
        @property GLBuffer IBO() { return _ibo; } // property can always be read
        /// Ditto
        @property GLBuffer IBO(GLBuffer ibo) { // write property
            assert (_state == State.UNUSED); // Can be modified ONLY when unused
            return _ibo = ibo;
        }

        /// Adds an non-generic attribute to the vertex specification.
        /// Params: role = what is the role of this attribute;
        /// n = 1, 2, 3 or 4, is the number of components of the attribute;
        /// For compatibility, you should not define more than 16 attributes
        void addLegacy(VertexAttribute.Role role, GLenum glType, int n)
        {
            assert(role != VertexAttribute.Role.GENERIC);
            assert(n > 0 && n <= 4);
            assert(_state == State.UNUSED);
            assert(isGLTypeSuitable(glType));
            _attributes ~= VertexAttribute(role, n, _currentOffset, glType, -1, null, GL_FALSE);
            _currentOffset += n * glTypeSize(glType);
        }

        /// Adds a generic attribute to the vertex specification.
        /// Params: role = what is the role of this attribute;
        /// n = 1, 2, 3 or 4, is the number of components of the attribute;
        /// For compatibility, you should not define more than 16 attributes
        void addGeneric(GLenum glType, int n, GLuint location, GLboolean normalize = GL_FALSE)
        {
            assert(n > 0 && n <= 4);
            assert(_state == State.UNUSED);
            assert(isGLTypeSuitable(glType));
            _attributes ~= VertexAttribute(VertexAttribute.Role.GENERIC, n, _currentOffset, glType, location, null, normalize);
            _currentOffset += n * glTypeSize(glType);
        }

        /// Adds a generic attribute to the vertex specification.
        /// Params: role = what is the role of this attribute;
        /// n = 1, 2, 3 or 4, is the number of components of the attribute;
        /// For compatibility, you should not define more than 16 attributes
        void addGeneric(GLenum glType, int n, string name, GLboolean normalize = GL_FALSE)
        {
            assert(n > 0 && n <= 4);
            assert(_state == State.UNUSED);
            assert(isGLTypeSuitable(glType));
            _attributes ~= VertexAttribute(VertexAttribute.Role.GENERIC, n, _currentOffset, glType, -1, name, normalize);
            _currentOffset += n * glTypeSize(glType);
        }

        /// Adds padding space to the vertex specification.
        /// This is useful for alignment. TODO: clarify
        void addDummyBytes(int nBytes)
        {
            assert(_state == State.UNUSED);
            _currentOffset += nBytes;
        }

        /// Returns the size of the Vertex; this size can be computer
        /// after you added all your attributes
        size_t getVertexSize() { return _currentOffset; }
    }

    private
    {
        enum State
        {
            UNUSED,
            USED
        }
        GLBuffer _vbo;      /// The Vertex BO this VertexSpecification refers to
        GLBuffer _ibo;      /// The Index BO this VertexSpecification refers to
        State _state;
        OpenGL _gl;
        VertexAttribute[] _attributes;
        size_t _currentOffset;
    }
}

/// Describes a single attribute in a vertex entry.
struct VertexAttribute
{
    /// Role of this vertex attribute.
    enum Role
    {
        POSITION,  /// This attribute is a position.
        COLOR,     /// This attribute is a color.
        TEX_COORD, /// This attribute is a texture coordinate.
        NORMAL,    /// This attribute is a normal.
        GENERIC    /// This attribute is a generic vertex attribute
    }

    // FIXME TODO should those be private?
    Role role;
    int n;
    size_t offset;
    GLenum glType;
    GLint genericLocation;
    string genericName;
    GLboolean normalize;

    package
    {
        /// Use this attribute.
        /// Throws: $(D OpenGLException) on error.
        void use(OpenGL gl, GLProgram program, GLsizei sizeOfVertex)
        {
            final switch (role)
            {
                case Role.POSITION:
                    glEnableClientState(GL_VERTEX_ARRAY);
                    glVertexPointer(n, glType, sizeOfVertex, cast(GLvoid *) offset);
                    break;

                case Role.COLOR:
                    glEnableClientState(GL_COLOR_ARRAY);
                    glColorPointer(n, glType, sizeOfVertex, cast(GLvoid *) offset);
                    break;

                case Role.TEX_COORD:
                    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
                    glTexCoordPointer(n, glType, sizeOfVertex, cast(GLvoid *) offset);
                    break;

                case Role.NORMAL:
                    glEnableClientState(GL_NORMAL_ARRAY);
                    assert(n == 3);
                    glNormalPointer(glType, sizeOfVertex, cast(GLvoid *) offset);
                    break;

               case Role.GENERIC:
                    if (genericLocation == -1)  {       // we need to recover the location of the attribute
                        assert(program !is null);
                        genericLocation = program.attrib(genericName).location;
                    }
                    glEnableVertexAttribArray(genericLocation);
                    glVertexAttribPointer(genericLocation, n, glType, normalize, sizeOfVertex, cast(GLvoid *) offset);
                    break;
            }

            gl.runtimeCheck();
        }

        /// Unuse this attribute.
        /// Throws: $(D OpenGLException) on error.
        void unuse(OpenGL gl)
        {
            final switch (role)
            {
                case Role.POSITION:
                    glDisableClientState(GL_VERTEX_ARRAY);
                    break;

                case Role.COLOR:
                    glDisableClientState(GL_COLOR_ARRAY);
                    break;

                case Role.TEX_COORD:
                    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
                    break;

                case Role.NORMAL:
                    glDisableClientState(GL_NORMAL_ARRAY);
                    break;

                case Role.GENERIC:
                    glDisableVertexAttribArray(genericLocation);
                    break;
            }
            gl.runtimeCheck();
        }
    }
}

private
{
    bool isGLTypeSuitable(GLenum t) pure nothrow
    {
        return (t == GL_BYTE  
             || t == GL_UNSIGNED_BYTE 
             || t == GL_SHORT 
             || t == GL_UNSIGNED_SHORT
             || t == GL_INT   
             || t == GL_UNSIGNED_INT 
//             || t == GL_HALF  
             || t == GL_FLOAT 
             || t == GL_DOUBLE);
    }

    size_t glTypeSize(GLenum t) pure nothrow
    {
        switch(t)
        {
            case GL_BYTE:
            case GL_UNSIGNED_BYTE: return 1;
//            case GL_HALF:
            case GL_SHORT:
            case GL_UNSIGNED_SHORT: return 2;
            case GL_INT:
            case GL_UNSIGNED_INT:
            case GL_FLOAT: return 4;
            case GL_DOUBLE: return 8;
            default: assert(false);
        }
    }
}
