using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace LadderGen
{
    public sealed class Instance
    {
        public string Body;
        public string Key;
        public Func<string, bool> Check;
    }

    internal static class Util
    {
        public static void Shuffle<T>(Random rng, IList<T> list)
        {
            for (int i = list.Count - 1; i > 0; i--)
            {
                int j = rng.Next(i + 1);
                T t = list[i]; list[i] = list[j]; list[j] = t;
            }
        }

        public static int[] Ints(string s)
        {
            return Regex.Matches(s, @"-?\d{1,9}").Cast<Match>()
                .Select(m => int.Parse(m.Value)).ToArray();
        }

        public static string[] Words(string s)
        {
            return Regex.Split(s.Trim(), @"[\s,;]+").Where(w => w.Length > 0).ToArray();
        }
    }

    // Inductive reasoning: infer a composed list transform from examples.
    public static class Induct
    {
        const int Len = 8;
        const int Examples = 6;

        static readonly string[] Names =
        {
            "reverse", "sort", "add", "mul", "rotate",
            "pairswap", "addindex", "prefix", "complement",
        };

        static readonly string[] Help =
        {
            "reverse: reverse the order of the list.",
            "sort: sort the list in ascending order.",
            "add c: add c to every element, modulo 10. c is 1 to 9.",
            "mul c: multiply every element by c, modulo 10. c is 3, 7 or 9.",
            "rotate c: move the first c elements to the end, in the same order. "
                + "c is 1 to 7.",
            "pairswap: swap the elements at positions 1-2, 3-4, 5-6 and 7-8.",
            "addindex: add its position to every element, modulo 10. "
                + "The first position is 0.",
            "prefix: replace every element with the sum of it and all elements "
                + "before it, modulo 10.",
            "complement: replace every element x with 9 - x.",
        };

        static bool HasParam(int op) { return op >= 2 && op <= 4; }

        static bool ValidParam(int op, int c)
        {
            switch (op)
            {
                case 2: return c >= 1 && c <= 9;
                case 3: return c == 3 || c == 7 || c == 9;
                case 4: return c >= 1 && c <= Len - 1;
                default: return true;
            }
        }

        static int RandomParam(Random rng, int op)
        {
            switch (op)
            {
                case 2: return rng.Next(1, 10);
                case 3: return new[] { 3, 7, 9 }[rng.Next(3)];
                case 4: return rng.Next(1, Len);
                default: return 0;
            }
        }

        static int[] Apply(int[] x, int op, int c)
        {
            var y = (int[])x.Clone();
            switch (op)
            {
                case 0: Array.Reverse(y); break;
                case 1: Array.Sort(y); break;
                case 2: for (int i = 0; i < Len; i++) y[i] = (x[i] + c) % 10; break;
                case 3: for (int i = 0; i < Len; i++) y[i] = (x[i] * c) % 10; break;
                case 4: for (int i = 0; i < Len; i++) y[i] = x[(i + c) % Len]; break;
                case 5:
                    for (int i = 0; i + 1 < Len; i += 2) { y[i] = x[i + 1]; y[i + 1] = x[i]; }
                    break;
                case 6: for (int i = 0; i < Len; i++) y[i] = (x[i] + i) % 10; break;
                case 7:
                    int s = 0;
                    for (int i = 0; i < Len; i++) { s = (s + x[i]) % 10; y[i] = s; }
                    break;
                case 8: for (int i = 0; i < Len; i++) y[i] = 9 - x[i]; break;
            }
            return y;
        }

        static int[] Run(List<int[]> prog, int[] x)
        {
            foreach (var step in prog) x = Apply(x, step[0], step[1]);
            return x;
        }

        static string Fmt(int[] x) { return "[" + string.Join(" ", x) + "]"; }

        static string StepText(int[] s)
        {
            return HasParam(s[0]) ? Names[s[0]] + " " + s[1] : Names[s[0]];
        }

        public static Instance Create(Random rng, int k)
        {
            List<int[]> prog;
            int[][] ins, outs;
            while (true)
            {
                prog = new List<int[]>();
                int last = -1;
                for (int i = 0; i < k; i++)
                {
                    int op;
                    do { op = rng.Next(Names.Length); } while (op == last);
                    last = op;
                    prog.Add(new[] { op, RandomParam(rng, op) });
                }
                ins = new int[Examples][];
                outs = new int[Examples][];
                bool identity = true;
                for (int e = 0; e < Examples; e++)
                {
                    ins[e] = Enumerable.Range(0, Len).Select(_ => rng.Next(10)).ToArray();
                    outs[e] = Run(prog, ins[e]);
                    if (!ins[e].SequenceEqual(outs[e])) identity = false;
                }
                if (!identity) break;
            }

            var help = Help.ToList();
            Util.Shuffle(rng, help);
            var sb = new StringBuilder();
            sb.AppendLine($"A hidden rule maps a list of {Len} digits to another list of {Len} digits.");
            sb.AppendLine($"The rule applies at most {k} operations from this library, in order.");
            sb.AppendLine("The same operation can occur more than once.");
            sb.AppendLine();
            foreach (var h in help) sb.AppendLine("- " + h);
            sb.AppendLine();
            sb.AppendLine("Examples:");
            for (int e = 0; e < Examples; e++) sb.AppendLine(Fmt(ins[e]) + " -> " + Fmt(outs[e]));
            sb.AppendLine();
            sb.AppendLine($"Find a rule of at most {k} operations that reproduces every example.");
            sb.AppendLine("Any rule that reproduces every example is correct.");
            sb.AppendLine();
            sb.Append("Answer format: ANSWER: the operations in order, separated by semicolons. "
                + "Example: ANSWER: add 3; reverse; rotate 2");

            var cIns = ins;
            var cOuts = outs;
            return new Instance
            {
                Body = sb.ToString(),
                Key = string.Join("; ", prog.Select(StepText)),
                Check = a => Verify(a, cIns, cOuts, k),
            };
        }

        static bool Verify(string answer, int[][] ins, int[][] outs, int k)
        {
            var prog = new List<int[]>();
            foreach (var part in answer.Split(';'))
            {
                var tok = part.Trim().ToLowerInvariant()
                    .Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                if (tok.Length == 0) continue;
                int op = Array.IndexOf(Names, tok[0]);
                if (op < 0) return false;
                int c = 0;
                if (HasParam(op))
                {
                    if (tok.Length != 2 || !int.TryParse(tok[1], out c)) return false;
                    if (!ValidParam(op, c)) return false;
                }
                else if (tok.Length != 1) return false;
                prog.Add(new[] { op, c });
            }
            if (prog.Count == 0 || prog.Count > k) return false;
            for (int e = 0; e < ins.Length; e++)
            {
                if (!Run(prog, ins[e]).SequenceEqual(outs[e])) return false;
            }
            return true;
        }
    }

    // Deduction: seat n people from clues that have exactly one solution.
    public static class Deduce
    {
        const long Budget = 3000000;

        static readonly string[] Pool =
        {
            "Ana", "Ben", "Cai", "Dev", "Eli", "Fay", "Gus", "Hal", "Ivy", "Jon",
            "Kit", "Lea", "Max", "Noa", "Oto", "Pia", "Quin", "Rui", "Sol", "Tea",
        };

        internal enum Kind { At, NotAt, LeftOf, Adjacent, NotAdjacent, Distance, End }

        internal struct Clue
        {
            public Kind T;
            public int A, B, P;
        }

        internal static bool Holds(Clue c, int[] pos, int n)
        {
            int a = pos[c.A];
            if (a < 0) return true;
            switch (c.T)
            {
                case Kind.At: return a == c.P;
                case Kind.NotAt: return a != c.P;
                case Kind.End: return a == 0 || a == n - 1;
            }
            int b = pos[c.B];
            if (b < 0) return true;
            switch (c.T)
            {
                case Kind.LeftOf: return a < b;
                case Kind.Adjacent: return Math.Abs(a - b) == 1;
                case Kind.NotAdjacent: return Math.Abs(a - b) != 1;
                case Kind.Distance: return Math.Abs(a - b) == c.P;
            }
            return true;
        }

        static Clue RandomTrue(Random rng, int[] seat, int[] personAt, int n)
        {
            while (true)
            {
                int r = rng.Next(100);
                int a = rng.Next(n);
                int b;
                do { b = rng.Next(n); } while (b == a);
                int sa = seat[a], sb = seat[b], d = Math.Abs(sa - sb);
                if (r < 5) return new Clue { T = Kind.At, A = a, P = sa };
                if (r < 20)
                {
                    int p;
                    do { p = rng.Next(n); } while (p == sa);
                    return new Clue { T = Kind.NotAt, A = a, P = p };
                }
                if (r < 45)
                {
                    return sa < sb
                        ? new Clue { T = Kind.LeftOf, A = a, B = b }
                        : new Clue { T = Kind.LeftOf, A = b, B = a };
                }
                if (r < 60)
                {
                    var side = new List<int>();
                    if (sa > 0) side.Add(sa - 1);
                    if (sa < n - 1) side.Add(sa + 1);
                    int other = personAt[side[rng.Next(side.Count)]];
                    return new Clue { T = Kind.Adjacent, A = a, B = other };
                }
                if (r < 75)
                {
                    if (d == 1) continue;
                    return new Clue { T = Kind.NotAdjacent, A = a, B = b };
                }
                if (r < 95)
                {
                    if (d < 2) continue;
                    return new Clue { T = Kind.Distance, A = a, B = b, P = d };
                }
                if (sa != 0 && sa != n - 1) continue;
                return new Clue { T = Kind.End, A = a };
            }
        }

        static string Text(Clue c, string[] name)
        {
            string a = name[c.A];
            switch (c.T)
            {
                case Kind.At: return $"{a} sits in seat {c.P + 1}.";
                case Kind.NotAt: return $"{a} does not sit in seat {c.P + 1}.";
                case Kind.LeftOf: return $"{a} sits somewhere to the left of {name[c.B]}.";
                case Kind.Adjacent: return $"{a} sits next to {name[c.B]}.";
                case Kind.NotAdjacent: return $"{a} does not sit next to {name[c.B]}.";
                case Kind.Distance:
                    return $"{a} and {name[c.B]} sit exactly {c.P} seats apart.";
                default: return $"{a} sits at one end of the row.";
            }
        }

        // -1 means the node budget ran out before the count was known.
        static int CountSolutions(List<Clue> clues, int n)
        {
            return new SeatSolver(n, clues, Budget).Count();
        }

        public static Instance Create(Random rng, int n)
        {
            if (n > Pool.Length) throw new ArgumentException($"deduce supports at most {Pool.Length} people.");
            var pool = Pool.ToList();
            Util.Shuffle(rng, pool);
            var name = pool.Take(n).ToArray();
            var seat = Enumerable.Range(0, n).ToArray();
            Util.Shuffle(rng, seat);
            var personAt = new int[n];
            for (int p = 0; p < n; p++) personAt[seat[p]] = p;

            List<Clue> clues;
            while (true)
            {
                clues = new List<Clue>();
                var seen = new HashSet<string>();
                int count = 0;
                while (clues.Count < 12 * n)
                {
                    var c = RandomTrue(rng, seat, personAt, n);
                    if (!seen.Add($"{c.T},{c.A},{c.B},{c.P}")) continue;
                    clues.Add(c);
                    if (clues.Count < n - 1) continue;
                    count = CountSolutions(clues, n);
                    if (count == 1) break;
                }
                if (count == 1) break;
            }

            var order = clues.ToList();
            Util.Shuffle(rng, order);
            foreach (var c in order)
            {
                clues.Remove(c);
                if (CountSolutions(clues, n) != 1) clues.Add(c);
            }
            Util.Shuffle(rng, clues);

            var sb = new StringBuilder();
            sb.AppendLine($"{n} people sit in a row of {n} seats, numbered 1 to {n} from left to right.");
            sb.AppendLine("Each seat holds exactly one person.");
            sb.AppendLine("People: " + string.Join(", ", name.OrderBy(x => x, StringComparer.Ordinal)));
            sb.AppendLine();
            sb.AppendLine("Clues:");
            for (int i = 0; i < clues.Count; i++) sb.AppendLine($"{i + 1}. {Text(clues[i], name)}");
            sb.AppendLine();
            sb.AppendLine("The clues have exactly one solution.");
            sb.AppendLine();
            sb.Append($"Answer format: ANSWER: the names in seat order, from seat 1 to seat {n}, "
                + "separated by spaces.");

            var key = Enumerable.Range(0, n).Select(s => name[personAt[s]]).ToArray();
            return new Instance
            {
                Body = sb.ToString(),
                Key = string.Join(" ", key),
                Check = a =>
                {
                    var w = Util.Words(a);
                    return w.Length == n && w.Zip(key, (x, y) =>
                        string.Equals(x, y, StringComparison.OrdinalIgnoreCase)).All(ok => ok);
                },
            };
        }
    }

    internal sealed class SeatSolver
    {
        readonly int n;
        readonly long budget;
        readonly List<Deduce.Clue>[] byPerson;
        readonly int[] order, pos;
        readonly bool[] used;
        long nodes;
        int count;
        bool aborted;

        public SeatSolver(int n, List<Deduce.Clue> clues, long budget)
        {
            this.n = n;
            this.budget = budget;
            byPerson = Enumerable.Range(0, n).Select(_ => new List<Deduce.Clue>()).ToArray();
            foreach (var c in clues)
            {
                byPerson[c.A].Add(c);
                if (c.B != c.A && UsesB(c)) byPerson[c.B].Add(c);
            }
            order = Enumerable.Range(0, n).OrderByDescending(p => byPerson[p].Count).ToArray();
            pos = Enumerable.Repeat(-1, n).ToArray();
            used = new bool[n];
        }

        static bool UsesB(Deduce.Clue c)
        {
            return c.T == Deduce.Kind.LeftOf || c.T == Deduce.Kind.Adjacent
                || c.T == Deduce.Kind.NotAdjacent || c.T == Deduce.Kind.Distance;
        }

        public int Count()
        {
            Rec(0);
            return aborted ? -1 : count;
        }

        bool Rec(int depth)
        {
            if (depth == n) { count++; return count < 2; }
            int p = order[depth];
            for (int s = 0; s < n; s++)
            {
                if (used[s]) continue;
                if (++nodes > budget) { aborted = true; return false; }
                pos[p] = s;
                used[s] = true;
                bool ok = true;
                foreach (var c in byPerson[p])
                {
                    if (!Deduce.Holds(c, pos, n)) { ok = false; break; }
                }
                bool go = !ok || Rec(depth + 1);
                pos[p] = -1;
                used[s] = false;
                if (!go) return false;
            }
            return true;
        }
    }

    // Code reading: execute a random program by hand.
    public static class Trace
    {
        const int Mod = 1000;

        abstract class Stmt { }

        sealed class Assign : Stmt { public int T, X, Y, Z, C; }

        sealed class IfElse : Stmt
        {
            public int Cond, X, Y, C;
            public List<Stmt> Then, Else;
        }

        sealed class Repeat : Stmt
        {
            public int K;
            public List<Stmt> Body;
        }

        static List<Stmt> Block(Random rng, int budget, int depth)
        {
            var list = new List<Stmt>();
            while (budget > 0)
            {
                int r = rng.Next(10);
                if (depth < 2 && budget >= 3 && r < 2)
                {
                    int inner = rng.Next(1, Math.Min(budget - 1, 4) + 1);
                    list.Add(new Repeat { K = rng.Next(2, 5), Body = Block(rng, inner, depth + 1) });
                    budget -= inner + 1;
                }
                else if (depth < 2 && budget >= 3 && r < 4)
                {
                    int room = Math.Min(budget - 1, 6);
                    int t = rng.Next(1, room);
                    int e = rng.Next(1, room - t + 1);
                    int cond = rng.Next(3);
                    int x = rng.Next(4), y;
                    do { y = rng.Next(4); } while (y == x);
                    list.Add(new IfElse
                    {
                        Cond = cond, X = x, Y = y, C = rng.Next(100, 900),
                        Then = Block(rng, t, depth + 1),
                        Else = Block(rng, e, depth + 1),
                    });
                    budget -= 1 + t + e;
                }
                else
                {
                    int kind = rng.Next(4);
                    list.Add(new Assign
                    {
                        T = kind, X = rng.Next(4), Y = rng.Next(4), Z = rng.Next(4),
                        C = kind == 3 ? rng.Next(2, 10) : rng.Next(1, 100),
                    });
                    budget--;
                }
            }
            return list;
        }

        static void Render(List<Stmt> list, string[] v, int indent, StringBuilder sb)
        {
            string pad = new string(' ', indent * 4);
            foreach (var s in list)
            {
                if (s is Assign a)
                {
                    string rhs;
                    switch (a.T)
                    {
                        case 0: rhs = $"{v[a.Y]} + {v[a.Z]}"; break;
                        case 1: rhs = $"{v[a.Y]} - {v[a.Z]}"; break;
                        case 2: rhs = $"{v[a.Y]} + {a.C}"; break;
                        default: rhs = $"{v[a.Y]} * {a.C}"; break;
                    }
                    sb.AppendLine($"{pad}{v[a.X]} = {rhs}");
                }
                else if (s is IfElse f)
                {
                    string cond;
                    switch (f.Cond)
                    {
                        case 0: cond = $"{v[f.X]} < {v[f.Y]}"; break;
                        case 1: cond = $"{v[f.X]} is even"; break;
                        default: cond = $"{v[f.X]} > {f.C}"; break;
                    }
                    sb.AppendLine($"{pad}if {cond}:");
                    Render(f.Then, v, indent + 1, sb);
                    sb.AppendLine($"{pad}else:");
                    Render(f.Else, v, indent + 1, sb);
                }
                else if (s is Repeat r)
                {
                    sb.AppendLine($"{pad}repeat {r.K} times:");
                    Render(r.Body, v, indent + 1, sb);
                }
            }
        }

        static void Exec(List<Stmt> list, int[] val)
        {
            foreach (var s in list)
            {
                if (s is Assign a)
                {
                    long r;
                    switch (a.T)
                    {
                        case 0: r = val[a.Y] + val[a.Z]; break;
                        case 1: r = val[a.Y] - val[a.Z]; break;
                        case 2: r = val[a.Y] + a.C; break;
                        default: r = (long)val[a.Y] * a.C; break;
                    }
                    val[a.X] = (int)(((r % Mod) + Mod) % Mod);
                }
                else if (s is IfElse f)
                {
                    bool b;
                    switch (f.Cond)
                    {
                        case 0: b = val[f.X] < val[f.Y]; break;
                        case 1: b = val[f.X] % 2 == 0; break;
                        default: b = val[f.X] > f.C; break;
                    }
                    Exec(b ? f.Then : f.Else, val);
                }
                else if (s is Repeat r)
                {
                    for (int i = 0; i < r.K; i++) Exec(r.Body, val);
                }
            }
        }

        public static Instance Create(Random rng, int statements)
        {
            var pool = "pqrstuvwxyz".Select(c => c.ToString()).ToList();
            Util.Shuffle(rng, pool);
            var v = pool.Take(4).ToArray();
            var val = Enumerable.Range(0, 4).Select(_ => rng.Next(0, 50)).ToArray();
            var prog = Block(rng, statements, 0);

            var sb = new StringBuilder();
            sb.AppendLine("Run this program by hand. All values are integers from 0 to 999.");
            sb.AppendLine("Every assignment stores its result modulo 1000. "
                + "For example, -3 is stored as 997 and 1204 as 204.");
            sb.AppendLine("\"repeat k times:\" runs its indented block k times. "
                + "\"if ... else\" runs exactly one of its two blocks.");
            sb.AppendLine();
            for (int i = 0; i < 4; i++) sb.AppendLine($"{v[i]} = {val[i]}");
            Render(prog, v, 0, sb);
            sb.AppendLine();
            sb.Append($"Answer format: ANSWER: the final values of {string.Join(" ", v)}, "
                + "in that order, separated by spaces.");

            Exec(prog, val);
            var key = val.ToArray();
            return new Instance
            {
                Body = sb.ToString(),
                Key = string.Join(" ", key),
                Check = a => Util.Ints(a).SequenceEqual(key),
            };
        }
    }

    // Planning: solve a 4x4 sliding puzzle within the scramble length.
    public static class Slide
    {
        const int W = 4;
        const int Cells = W * W;

        static bool IsGoal(int[] b)
        {
            for (int i = 0; i < Cells - 1; i++) if (b[i] != i + 1) return false;
            return b[Cells - 1] == 0;
        }

        static bool Adjacent(int i, int j)
        {
            int ri = i / W, ci = i % W, rj = j / W, cj = j % W;
            return Math.Abs(ri - rj) + Math.Abs(ci - cj) == 1;
        }

        static string Grid(int[] b)
        {
            var sb = new StringBuilder();
            for (int r = 0; r < W; r++)
            {
                var row = Enumerable.Range(0, W)
                    .Select(c => b[r * W + c] == 0 ? " ." : b[r * W + c].ToString().PadLeft(2));
                sb.AppendLine(string.Join(" ", row));
            }
            return sb.ToString();
        }

        public static Instance Create(Random rng, int k)
        {
            int[] start;
            List<int> moved;
            while (true)
            {
                var b = Enumerable.Range(1, Cells - 1).Append(0).ToArray();
                int blank = Cells - 1, prev = -1;
                moved = new List<int>();
                for (int i = 0; i < k; i++)
                {
                    var next = Enumerable.Range(0, Cells)
                        .Where(j => j != prev && Adjacent(blank, j)).ToList();
                    int nb = next[rng.Next(next.Count)];
                    moved.Add(b[nb]);
                    b[blank] = b[nb];
                    b[nb] = 0;
                    prev = blank;
                    blank = nb;
                }
                if (!IsGoal(b)) { start = b; break; }
            }
            moved.Reverse();

            var goal = Enumerable.Range(1, Cells - 1).Append(0).ToArray();
            var sb = new StringBuilder();
            sb.AppendLine("A 4x4 sliding puzzle. \".\" is the empty cell. Start:");
            sb.AppendLine();
            sb.Append(Grid(start));
            sb.AppendLine();
            sb.AppendLine("Goal:");
            sb.AppendLine();
            sb.Append(Grid(goal));
            sb.AppendLine();
            sb.AppendLine("A move slides one tile that is next to the empty cell (up, down, left or "
                + "right, not diagonal) into the empty cell. Name each move by its tile number.");
            sb.AppendLine($"Reach the goal in at most {k} moves. A solution with {k} moves exists.");
            sb.AppendLine();
            sb.Append("Answer format: ANSWER: the tile numbers in move order, separated by spaces.");

            var s0 = start;
            return new Instance
            {
                Body = sb.ToString(),
                Key = string.Join(" ", moved),
                Check = a => Verify(a, s0, k),
            };
        }

        static bool Verify(string answer, int[] start, int k)
        {
            var moves = Util.Ints(answer);
            if (moves.Length == 0 || moves.Length > k) return false;
            var b = (int[])start.Clone();
            int blank = Array.IndexOf(b, 0);
            foreach (int t in moves)
            {
                if (t < 1 || t >= Cells) return false;
                int at = Array.IndexOf(b, t);
                if (!Adjacent(at, blank)) return false;
                b[blank] = t;
                b[at] = 0;
                blank = at;
            }
            return IsGoal(b);
        }
    }

    public static class Stats
    {
        static double[] PavaDecreasing(double[] y, double[] w)
        {
            var val = new List<double>();
            var wt = new List<double>();
            var len = new List<int>();
            for (int i = 0; i < y.Length; i++)
            {
                val.Add(y[i]); wt.Add(w[i]); len.Add(1);
                while (val.Count > 1 && val[val.Count - 2] < val[val.Count - 1])
                {
                    int a = val.Count - 2, b = val.Count - 1;
                    double nw = wt[a] + wt[b];
                    val[a] = (val[a] * wt[a] + val[b] * wt[b]) / nw;
                    wt[a] = nw;
                    len[a] += len[b];
                    val.RemoveAt(b); wt.RemoveAt(b); len.RemoveAt(b);
                }
            }
            var fit = new double[y.Length];
            int k = 0;
            for (int g = 0; g < val.Count; g++)
                for (int j = 0; j < len[g]; j++) fit[k++] = val[g];
            return fit;
        }

        /// <summary>
        /// Difficulty at which the monotone success curve crosses 50%,
        /// interpolated on a log scale. censor is -1 below the scale,
        /// +1 above it (value is then one growth step past the last level).
        /// </summary>
        public static double D50(double[] d, int[] ok, int[] n, out int censor)
        {
            int levels = d.Length;
            var rate = new double[levels];
            var w = new double[levels];
            for (int i = 0; i < levels; i++)
            {
                rate[i] = n[i] == 0 ? 0 : ok[i] / (double)n[i];
                w[i] = Math.Max(n[i], 1e-9);
            }
            var f = PavaDecreasing(rate, w);
            double g = Math.Pow(d[levels - 1] / d[0], 1.0 / (levels - 1));
            int j = Array.FindIndex(f, x => x < 0.5);
            if (j < 0) { censor = 1; return d[levels - 1] * g; }
            if (j == 0) { censor = -1; return d[0] / g; }
            censor = 0;
            double t = (f[j - 1] - 0.5) / (f[j - 1] - f[j]);
            return Math.Exp(Math.Log(d[j - 1]) + t * (Math.Log(d[j]) - Math.Log(d[j - 1])));
        }

        static int[] Resample(Random rng, int[] ok, int[] n)
        {
            var o = new int[ok.Length];
            for (int i = 0; i < ok.Length; i++)
            {
                double p = n[i] == 0 ? 0 : ok[i] / (double)n[i];
                for (int t = 0; t < n[i]; t++) if (rng.NextDouble() < p) o[i]++;
            }
            return o;
        }

        /// <summary>
        /// Bootstrap samples of candidate d50 over the best baseline d50.
        /// </summary>
        public static double[] BootRatios(
            double[] dC, int[] okC, int[] nC,
            double[][] dB, int[][] okB, int[][] nB, int reps, int seed)
        {
            var rng = new Random(seed);
            var res = new double[reps];
            for (int r = 0; r < reps; r++)
            {
                double c = D50(dC, Resample(rng, okC, nC), nC, out _);
                double b = 0;
                for (int j = 0; j < dB.Length; j++)
                {
                    b = Math.Max(b, D50(dB[j], Resample(rng, okB[j], nB[j]), nB[j], out _));
                }
                res[r] = c / b;
            }
            return res;
        }

        public static double[] Monotone(int[] ok, int[] n)
        {
            var rate = new double[ok.Length];
            var w = new double[ok.Length];
            for (int i = 0; i < ok.Length; i++)
            {
                rate[i] = n[i] == 0 ? 0 : ok[i] / (double)n[i];
                w[i] = Math.Max(n[i], 1e-9);
            }
            return PavaDecreasing(rate, w);
        }

        /// <summary>
        /// Bootstrap samples of mean(a) - mean(b). a[i] and b[i] are the
        /// two models' results on the same item i.
        /// </summary>
        public static double[] BootPairedDiff(bool[] a, bool[] b, int reps, int seed)
        {
            var rng = new Random(seed);
            var res = new double[reps];
            int n = a.Length;
            for (int r = 0; r < reps; r++)
            {
                int d = 0;
                for (int t = 0; t < n; t++)
                {
                    int i = rng.Next(n);
                    d += (a[i] ? 1 : 0) - (b[i] ? 1 : 0);
                }
                res[r] = d / (double)n;
            }
            return res;
        }
    }
}
