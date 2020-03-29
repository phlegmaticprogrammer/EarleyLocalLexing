# EarleyLocalLexing

This is an implementation of *parameterized local lexing* which is an extension of Earley's algorithm. 

Background information on (parameterized) local lexing can be found in these two papers:

- [**Local Lexing** — *Steven Obua*, *Phil Scott*, *Jacques Fleuriot*](https://arxiv.org/abs/1702.03277)
- [**Parameterized Local Lexing** — *Steven Obua*](https://arxiv.org/abs/1704.04215)

There exists also a [formal correctness proof in Isabelle](https://www.isa-afp.org/entries/LocalLexing.html) of the basic local lexing algorithm.

This implementation is not meant to be used directly by an end-user working on a concrete parsing project. Instead, it provides one of the backends (currently, the only one) for LocalLexingKit. 

Nevertheless, for the user who is inclined to make direct use of this library, the best starting point is probably the documentation for `EarleyParser`.



