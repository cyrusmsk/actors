import std.concurrency;
import std.stdio;
import std.random;
import std.math;
import std.algorithm;
import std.range;
import core.thread;
import std.datetime.stopwatch;
import raylib;

// ----------------------
// Color Mapping for Raylib
// ----------------------
Color getColor(ubyte c)
{
    switch (c)
    {
    case 0:
        return Colors.RED;
    case 1:
        return Colors.BLUE;
    case 2:
        return Colors.GREEN;
    case 3:
        return Colors.ORANGE;
    case 4:
        return Colors.PURPLE;
    case 5:
        return Colors.PINK;
    case 6:
        return Colors.YELLOW;
    default:
        return Colors.GRAY; // uncolored
    }
}

// ----------------------
// Messages
// ----------------------
struct ColorMsg
{
    Tid sender;
    ubyte color;
}

struct InitMsg
{
    ubyte initialColor;
    ubyte threshold;
    Tid coordinator;
    immutable(Tid)[] actors;
}

struct ColoredMsg
{
    Tid who;
    ubyte color;
}

struct StatusReply
{
    bool colored;
}

struct StopActor
{
    bool status;
}

// ----------------------
// Dot Actor
// ----------------------
void dotActor(
    int id,
    double x,
    double y,
    immutable(double)[] xs,
    immutable(double)[] ys
)
{
    ubyte color = 255;
    ubyte threshold;
    Tid coordinator;
    ubyte[ubyte] freq;
    Tid currentTarget;
    size_t neighborIndex = 0;
    immutable(Tid)[] actors;
    bool currentTargetColored = true;

    auto N = xs.length;
    long[] sortedNeighbors;
    sortedNeighbors.length = N - 1;
    long idx = 0;
    foreach (long i; 0 .. N)
        if (i != id)
            sortedNeighbors[idx++] = i;

    sortedNeighbors.sort!((a, b) =>
            sqrt((x - xs[a]) ^^ 2 + (y - ys[a]) ^^ 2) <
            sqrt((x - xs[b]) ^^ 2 + (y - ys[b]) ^^ 2)
    );
    bool running = true;

    while (running)
    {
        receiveTimeout(dur!"msecs"(5),
            (InitMsg msg) {
            color = msg.initialColor;
            threshold = msg.threshold;
            coordinator = msg.coordinator;
            actors = msg.actors;
            Thread.sleep(dur!"msecs"(5));
            if (color != 255)
                send(coordinator, ColoredMsg(thisTid, color));
        },
            (ColorMsg msg) {
            if (color == 255)
            {
                freq[msg.color]++;
                if (freq[msg.color] >= threshold)
                {
                    color = msg.color;
                    send(coordinator, ColoredMsg(thisTid, color));
                }
            }
            else
            {
                // already colored: inform sender
                send(msg.sender, StatusReply(true));
            }
        },
            (StatusReply reply) {
            if (reply.colored)
            {
                neighborIndex++;
            }
        },
            (StopActor sa) {
            if (sa.status)
            {
                running = false;
                return;
            }
        }
        );

        if (color != 255 && neighborIndex < sortedNeighbors.length)
        {
            long targetIndex = sortedNeighbors[neighborIndex];
            currentTarget = cast(Tid) actors[targetIndex];
            send(currentTarget, ColorMsg(thisTid, color));
        }

        Thread.sleep(dur!"msecs"(5));
    }
}

// ----------------------
// Main
// ----------------------
void main()
{
    enum totalNodes = 800;
    enum THRESHOLD = 3;

    bool[Tid] coloredMap;
    ubyte[Tid] colorsMap; // store each node's color
    int coloredCount = 0;

    Tid[] actors;
    actors.length = totalNodes;

    auto xs = totalNodes.iota.map!(e => uniform(50.0, 750.0)).array;
    auto ys = totalNodes.iota.map!(e => uniform(50.0, 550.0)).array;

    // spawn actors
    foreach (i; 0 .. totalNodes)
        actors[i] = spawn(&dotActor, i, xs[i], ys[i], xs.idup, ys.idup);

    // initialize actors
    foreach (i; 0 .. totalNodes)
    {
        ubyte initialColor = 255;
        if (i < 4)
            initialColor = cast(ubyte) i;
        send(actors[i], InitMsg(initialColor, THRESHOLD, thisTid, cast(immutable(Tid)[]) actors));
    }

    // ----------------------
    // Initialize Raylib
    // ----------------------
    InitWindow(800, 600, "Actor Color Diffusion");
    SetTargetFPS(60);

    StopWatch sw;
    sw.start();

    while (coloredCount < totalNodes)
    {
        BeginDrawing();
        ClearBackground(Colors.RAYWHITE);
        foreach (i; 0 .. totalNodes)
        {
            DrawCircle(cast(int) xs[i], cast(int) ys[i], 10, getColor(colorsMap.get(actors[i], 255U)));
        }
        EndDrawing();
        receiveTimeout(dur!"msecs"(1),
            (ColoredMsg msg) {
            auto p = msg.who in coloredMap;
            if (p is null)
            {
                writeln("Coordinator recieved from ", msg.who);
                coloredMap[msg.who] = true;
                colorsMap[msg.who] = msg.color;
                coloredCount++;
                writeln("Colored: ", coloredCount, "/", totalNodes);
            }
        }
        );
    }

    sw.stop();
    foreach (t; actors)
        send(t, StopActor(true));
    writeln("All nodes colored!");
    writeln("Time: ", sw.peek.total!"msecs", " ms");

    while (!WindowShouldClose())
    {
        BeginDrawing();
        ClearBackground(Colors.RAYWHITE);
        foreach (i; 0 .. totalNodes)
        {
            DrawCircle(cast(int) xs[i], cast(int) ys[i], 10, getColor(colorsMap.get(actors[i], 255U)));
        }
        EndDrawing();
        if (GetKeyPressed() != 0)
        {
            break;
        }
    }
    CloseWindow();
}
