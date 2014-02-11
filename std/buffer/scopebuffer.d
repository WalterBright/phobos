/*
 * Copyright: 2014 by Digital Mars
 * License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Walter Bright
 */

module std.buffer.scopebuffer;


/**************************************
 * ScopeBuffer encapsulates using a local array as a temporary buffer.
 * It is initialized with the local array that should be large enough for
 * most uses. If the need exceeds the size, ScopeBuffer will resize it
 * using malloc() and friends.
 * ScopeBuffer is an OutputRange.
 * Example:
---
import core.stdc.stdio;
void main()
{
    char[2] buf = void;
    auto textbuf = ScopeBuffer!char(buf);

    // Put characters and strings into textbuf, verify they got there
    textbuf.put('a');
    textbuf.put('x');
    textbuf.put("abc");
    assert(textbuf.length == 5);
    assert(textbuf[1..3] == "xa");
    assert(textbuf[3] == 'b');

    // Can use it like a stack
    textbuf.pop();
    assert(textbuf[0..textbuf.length] == "axab");

    // Can shrink it
    textbuf.length = 3;
    assert(textbuf[0..textbuf.length] == "axa");
    assert(textbuf[textbuf.length - 1] == 'a');
    assert(textbuf[1..3] == "xa");

    textbuf.put('z');
    assert(textbuf[] == "axaz");

    // Can shrink it to 0 size, and reuse same memory
    textbuf.length = 0;
}
---
 */

//debug=ScopeBuffer;

struct ScopeBuffer(T, U = uint)
if(is(U == uint) || is(U == size_t))
{
    import core.stdc.stdlib : malloc, realloc, free;
    import core.stdc.string : memcpy;
    //import std.stdio;

    /**************************
     * Initialize with buf to use as scratch buffer space.
     * Params:
     *  buf     Scratch buffer space, must have length that is even
     * Example:
     * ---
     * ubyte[10] tmpbuf = void;
     * auto sbuf = ScopeBuffer(tmpbuf);
     * ---
     */
    this(T[] buf)
    {
        assert(!(buf.length & resized));
        this.buf = buf.ptr;
        this.bufLen = cast(U)buf.length;
    }

    /**************************
     * Destructor releases any memory used.
     * This will invalidate any references returned by the [] operator.
     */
    ~this()
    {
        debug(ScopeBuffer) buf[0 .. bufLen] = 0;
        if (bufLen & resized)
            free(buf);
        buf = null;
        bufLen = 0;
        i = 0;
    }

    /************************
     * Append element c to the buffer.
     */
    void put(T c)
    {
        /* j will get enregistered, while i will not because resize() may change i
         */
        const j = i;
        if (j == bufLen)
        {
            resize(j * 2 + 16);
        }
        buf[j] = c;
        i = j + 1;
    }

    /************************
     * Append string s to the buffer.
     */
    void put(const(T)[] s)
    {
        const newlen = i + s.length;
        const len = bufLen;
        if (newlen > len)
            resize(newlen <= len * 2 ? len * 2 : newlen);
        buf[i .. newlen] = s[];
        i = cast(U)newlen;
    }

    /******
     * Retrieve a slice into the result.
     * Returns:
     *  A slice into the temporary buffer that is only
     *  valid until the next put() or ScopeBuffer goes out of scope.
     */
    @system T[] opSlice(size_t lwr, size_t upr)
        in
        {
            assert(lwr <= bufLen);
            assert(upr <= bufLen);
            assert(lwr <= upr);
        }
    body
    {
        return buf[lwr .. upr];
    }

    /******
     * Retrieve the result.
     * Returns:
     *  A slice into the temporary buffer that is only
     *  valid until the next put() or ScopeBuffer goes out of scope.
     */
    @system T[] opSlice()
    {
        assert(i <= bufLen);
        return buf[0 .. i];
    }

    /*******
     * Retrieve the element at index i.
     */
    T opIndex(size_t i)
    {
        assert(i < bufLen);
        return buf[i];
    }

    /*******************
     * Returns:
     * the last element put into the ScopeBuffer,
     * and decrements the length.
     */
    T pop()
    {
        assert(i - 1 < bufLen);
        return buf[--i];
    }

    /***
     * Returns:
     *  the number of elements in the ScopeBuffer
     */
    @property size_t length()
    {
        return i;
    }

    /***
     * Used to set the length of the buffer,
     * typically to set it to 0.
     */
    @property void length(size_t i)
        in
        {
            assert(i <= bufLen);
        }
    body
    {
        this.i = cast(U)i;
    }

  private:
    T* buf;
    // Using uint instead of size_t so the struct fits in 2 registers in 64 bit code
    U bufLen;
    enum resized = 1;         // this bit is set in bufLen if we control the memory
    U i;

    void resize(size_t newsize)
    {
        //writefln("%s: oldsize %s newsize %s", id, buf.length, newsize);
        void* p;
        newsize |= resized;
        if (bufLen & resized)
        {
            /* Prefer realloc when possible
             */
            p = realloc(buf, newsize * T.sizeof);
            if (!p)
                assert(0);      // check stays even in -release mode
        }
        else
        {
            p = malloc(newsize * T.sizeof);
            if (!p)
                assert(0);
            memcpy(p, buf, i * T.sizeof);
            debug(ScopeBuffer) buf[0 .. bufLen] = 0;
        }
        buf = cast(T*)p;
        bufLen = cast(U)newsize;

        /* This function is called only rarely,
         * inlining results in poorer register allocation.
         */
        version (DigitalMars)
            /* With dmd, a fake loop will prevent inlining.
             * Using a hack until a language enhancement is implemented.
             */
            while (1) { break; }
    }
}


//uint version
unittest
{
    import core.stdc.stdio;
    import std.range;

    char[2] tmpbuf = void;
    {
    // Exercise all the lines of code except for assert(0)'s
    auto textbuf = ScopeBuffer!char(tmpbuf);

    static assert(isOutputRange!(ScopeBuffer!char, char));

    textbuf.put('a');
    textbuf.put('x');
    textbuf.put("abc");         // tickle put([])'s resize
    assert(textbuf.length == 5);
    assert(textbuf[1..3] == "xa");
    assert(textbuf[3] == 'b');

    textbuf.pop();
    assert(textbuf[0..textbuf.length] == "axab");

    textbuf.length = 3;
    assert(textbuf[0..textbuf.length] == "axa");
    assert(textbuf[textbuf.length - 1] == 'a');
    assert(textbuf[1..3] == "xa");

    textbuf.put(cast(dchar)'z');
    assert(textbuf[] == "axaz");

    textbuf.length = 0;                 // reset for reuse
    assert(textbuf.length == 0);

    foreach (char c; "asdf;lasdlfaklsdjfalksdjfa;lksdjflkajsfdasdfkja;sdlfj")
    {
        textbuf.put(c); // tickle put(c)'s resize
    }
    assert(textbuf[] == "asdf;lasdlfaklsdjfalksdjfa;lksdjflkajsfdasdfkja;sdlfj");
    } // run destructor on textbuf here
}


//size_t version
unittest
{
    import core.stdc.stdio;
    import std.range;

    char[2] tmpbuf = void;
    {
    // Exercise all the lines of code except for assert(0)'s
    auto textbuf = ScopeBuffer!(char, size_t)(tmpbuf);

    static assert(isOutputRange!(ScopeBuffer!char, char));

    textbuf.put('a');
    textbuf.put('x');
    textbuf.put("abc");         // tickle put([])'s resize
    assert(textbuf.length == 5);
    assert(textbuf[1..3] == "xa");
    assert(textbuf[3] == 'b');

    textbuf.pop();
    assert(textbuf[0..textbuf.length] == "axab");

    textbuf.length = 3;
    assert(textbuf[0..textbuf.length] == "axa");
    assert(textbuf[textbuf.length - 1] == 'a');
    assert(textbuf[1..3] == "xa");

    textbuf.put(cast(dchar)'z');
    assert(textbuf[] == "axaz");

    textbuf.length = 0;                 // reset for reuse
    assert(textbuf.length == 0);

    foreach (char c; "asdf;lasdlfaklsdjfalksdjfa;lksdjflkajsfdasdfkja;sdlfj")
    {
        textbuf.put(c); // tickle put(c)'s resize
    }
    assert(textbuf[] == "asdf;lasdlfaklsdjfalksdjfa;lksdjflkajsfdasdfkja;sdlfj");
    } // run destructor on textbuf here
}
