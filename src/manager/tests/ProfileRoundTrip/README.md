# Profile serialization regression

Run `dotnet run --project tests/ProfileRoundTrip` from the repository root.
Requires .NET 10 and the same UI/parser packages as the Manager.

The test compiles the production view-model files and checks both values of
RIFE ensemble through profile export to disk and import from disk. It creates isolated fixture
configuration under its output directory; no installed configuration, UI window,
model loading or component download is used. A failed round trip exits nonzero.
