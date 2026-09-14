"""Display-only bindings must never write localized text back to user profiles."""
from pathlib import Path
p=Path('manager/AnimeJaNaiConfEditor/Views/MainWindow.axaml')
s=p.read_text(encoding='utf-8')
old='{Binding ProfileName, Converter={x:Static local:LocalizedTextConverter.Instance}}'
assert s.count(old)==2
s=s.replace(old,'{Binding ProfileName, Mode=OneWay, Converter={x:Static local:LocalizedTextConverter.Instance}}')
p.write_text(s,encoding='utf-8')
p=Path('manager/AnimeJaNaiConfEditor/ManagerLanguage.cs')
s=p.read_text(encoding='utf-8')
s=s.replace('=> null;','=> Avalonia.AvaloniaProperty.UnsetValue;')
p.write_text(s,encoding='utf-8')
