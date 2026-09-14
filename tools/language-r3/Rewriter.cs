using System.Text.Json;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using var doc=JsonDocument.Parse(File.ReadAllText(args[0]));
var map=JsonSerializer.Deserialize<Dictionary<string,string>>(doc.RootElement.GetProperty("translations"))!;
var known=map.Keys.Concat(map.Values).ToHashSet(StringComparer.Ordinal);
known.ExceptWith(new[]{"Standard","Sharp","Static","Dynamic","Static ONNX","installed","optional","OK"});
known.RemoveWhere(s=>System.Text.RegularExpressions.Regex.IsMatch(s,"^[a-z][a-z0-9_-]+$"));
int total=0;
foreach(string file in args.Skip(1))
{
    var source=CSharpSyntaxTree.ParseText(File.ReadAllText(file));
    if(source.GetDiagnostics().Any(d=>d.Severity==DiagnosticSeverity.Error))throw new Exception("Invalid input "+file);
    var rewriter=new Rewrite(known);var root=rewriter.Visit(source.GetRoot())!;string result=root.ToFullString();
    if(CSharpSyntaxTree.ParseText(result).GetDiagnostics().Any(d=>d.Severity==DiagnosticSeverity.Error))throw new Exception("Invalid generated C# "+file);
    File.WriteAllText(file,result);total+=rewriter.Count;
}
Console.WriteLine($"Localized {total} C# display expressions using Roslyn; identifiers unchanged.");
sealed class Rewrite(HashSet<string> known):CSharpSyntaxRewriter
{
    public int Count;
    static bool ConstantContext(SyntaxNode node)=>node.Ancestors().Any(n=>n is AttributeSyntax or ConstantPatternSyntax or CaseSwitchLabelSyntax
        ||n is FieldDeclarationSyntax f&&f.Modifiers.Any(SyntaxKind.ConstKeyword)
        ||n is LocalDeclarationStatementSyntax l&&l.Modifiers.Any(SyntaxKind.ConstKeyword));
    public override SyntaxNode? VisitLiteralExpression(LiteralExpressionSyntax node)
    {
        if(node.IsKind(SyntaxKind.StringLiteralExpression)&&known.Contains(node.Token.ValueText)&&!ConstantContext(node))
        {Count++;return SyntaxFactory.ParseExpression("AnimeJaNai.Localization.UiText.T("+node.WithoutTrivia()+")").WithTriviaFrom(node);}
        return base.VisitLiteralExpression(node);
    }
    public override SyntaxNode? VisitInterpolatedStringExpression(InterpolatedStringExpressionSyntax node)
    {
        string format="";int index=0;
        foreach(var c in node.Contents)
        {
            if(c is InterpolatedStringTextSyntax t)format+=t.TextToken.ValueText;
            else if(c is InterpolationSyntax i)format+="{"+(index++)+(i.AlignmentClause?.ToString()??"")+(i.FormatClause?.ToString()??"")+"}";
        }
        if(known.Contains(format)&&!ConstantContext(node))
        {Count++;return SyntaxFactory.ParseExpression("AnimeJaNai.Localization.UiText.F("+node.WithoutTrivia()+")").WithTriviaFrom(node);}
        return base.VisitInterpolatedStringExpression(node);
    }
}
