using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

builder.Host.UseWindowsService(options =>
{
    options.ServiceName = "InstanaLab-InventoryService";
});

builder.Services.AddOpenApi();

var app = builder.Build();

// UI: http://localhost:8081/scalar/v1
app.MapOpenApi();
app.MapScalarApiReference();

var catalog = new Dictionary<int, InventoryProduct>
{
    [1] = new(1, "Laptop",    50),
    [2] = new(2, "Mouse",     200),
    [3] = new(3, "Keyboard",  150),
    [4] = new(4, "Monitor",   30),
    [5] = new(5, "Headset",   80)
};

app.MapGet("/inventory", () => Results.Ok(catalog.Values))
   .WithName("GetInventory");

app.MapGet("/inventory/{productId:int}", (int productId) =>
{
    if (!catalog.TryGetValue(productId, out var product))
        return Results.NotFound(new { Error = $"Product {productId} not found" });
    return Results.Ok(product);
})
.WithName("GetInventoryByProduct");

app.MapPost("/inventory/reserve", (ReserveRequest request) =>
{
    if (!catalog.TryGetValue(request.ProductId, out var product))
        return Results.NotFound(new { Error = $"Product {request.ProductId} not found" });

    if (product.Stock < request.Quantity)
        return Results.BadRequest(new { Error = "Insufficient stock", Available = product.Stock });

    catalog[request.ProductId] = product with { Stock = product.Stock - request.Quantity };

    return Results.Ok(new
    {
        Reserved  = request.Quantity,
        ProductId = request.ProductId,
        Remaining = catalog[request.ProductId].Stock
    });
})
.WithName("ReserveStock");

app.Run();

record InventoryProduct(int ProductId, string Name, int Stock);
record ReserveRequest(int ProductId, int Quantity);
