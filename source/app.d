import std.concurrency;
import std.stdio;
import std.random;
import std.math;
import std.algorithm;
import std.range;
import core.thread;
import std.datetime.stopwatch;

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

struct ColorRequest
{
    Tid requester;
    Tid target;
}

struct ColorResponse
{
    bool targetColored;
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

    while (true)
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
                writeln("finish");
                return;
            }
        },
            (ColorResponse cr) {
            writeln("got result that currentTarget ", cr.targetColored);
            currentTargetColored = cr.targetColored;
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
    enum totalNodes = 100;
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
        if (i < 1)
            initialColor = cast(ubyte) i;
        send(actors[i], InitMsg(initialColor, THRESHOLD, thisTid, cast(immutable(Tid)[]) actors));
    }

    StopWatch sw;
    sw.start();

    while (coloredCount < totalNodes)
    {
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
        },
            (ColorRequest msg) {
            send(msg.requester, ColorResponse(coloredMap.get(msg.target, false)));
        }
        );
    }

    sw.stop();
    foreach (t; actors)
        send(t, StopActor(true));

    Thread.sleep(dur!"seconds"(1));
    writeln("\nAll nodes colored!");
    writeln("Time: ", sw.peek.total!"msecs", " ms");
}
