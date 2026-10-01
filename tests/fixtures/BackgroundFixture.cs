using System;
using System.Text;

public static class BackgroundFixture {
    public static int Main() {
        Console.InputEncoding = new UTF8Encoding(false);
        Console.OutputEncoding = new UTF8Encoding(false);
        string value = Console.ReadLine();
        if (String.IsNullOrEmpty(value)) return 2;
        Console.WriteLine("echo:" + value);
        Console.Error.WriteLine("Set-Cookie: fixture");
        Console.WriteLine("stdout-tail");
        Console.Error.WriteLine("stderr-tail");
        return 0;
    }
}
