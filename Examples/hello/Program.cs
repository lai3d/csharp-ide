namespace Hello;

public static class Program
{
    public static void Main(string[] args)
    {
        var greeter = new Greeter("World");
        Console.WriteLine(greeter.Greet());
        int unused = "oops";
    }
}

public record Greeter(string Name)
{
    public string Greet() => $"Hello, {Name}!";
}
