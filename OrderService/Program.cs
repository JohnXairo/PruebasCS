using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

builder.Host.UseWindowsService(options =>
{
    options.ServiceName = "InstanaLab-OrderService";
});

builder.Services.AddOpenApi();
builder.Services.AddHttpClient("InventoryClient", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Services:InventoryService"] ?? "http://localhost:8081");
});
builder.Services.AddHttpClient("NotificationClient", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Services:NotificationService"] ?? "http://localhost:8082");
});

var app = builder.Build();

// UI: http://localhost:8080/scalar/v1
app.MapOpenApi();
app.MapScalarApiReference();

// GET /orders
app.MapGet("/orders", () =>
{
    var orders = new[]
    {
        new { Id = 1, Product = "Laptop",   Quantity = 2, Status = "Pending" },
        new { Id = 2, Product = "Mouse",    Quantity = 5, Status = "Shipped" },
        new { Id = 3, Product = "Keyboard", Quantity = 1, Status = "Delivered" }
    };
    return Results.Ok(orders);
})
.WithName("GetOrders");

// GET /orders/{id}
app.MapGet("/orders/{id:int}", (int id) =>
{
    if (id <= 0) return Results.NotFound();
    return Results.Ok(new { Id = id, Product = "Sample Product", Quantity = 1, Status = "Processing" });
})
.WithName("GetOrderById");

// POST /orders
app.MapPost("/orders", async (CreateOrderRequest request, IHttpClientFactory factory) =>
{
    var inventoryClient = factory.CreateClient("InventoryClient");
    var inventoryResponse = await inventoryClient.GetAsync($"/inventory/{request.ProductId}");

    if (!inventoryResponse.IsSuccessStatusCode)
        return Results.Problem("Inventory service unavailable", statusCode: 503);

    var inventory = await inventoryResponse.Content.ReadFromJsonAsync<InventoryItem>();

    if (inventory is null || inventory.Stock < request.Quantity)
        return Results.BadRequest(new { Error = "Insufficient stock", Available = inventory?.Stock ?? 0 });

    var reserveResponse = await inventoryClient.PostAsJsonAsync("/inventory/reserve", new
    {
        ProductId = request.ProductId,
        Quantity  = request.Quantity
    });

    if (!reserveResponse.IsSuccessStatusCode)
        return Results.Problem("Could not reserve stock", statusCode: 503);

    var notifClient = factory.CreateClient("NotificationClient");
    await notifClient.PostAsJsonAsync("/notifications", new
    {
        To      = request.CustomerEmail,
        Subject = $"Order confirmed - product {request.ProductId}",
        Body    = $"Your order of {request.Quantity} unit(s) has been placed."
    });

    var newOrder = new
    {
        Id        = Random.Shared.Next(1000, 9999),
        ProductId = request.ProductId,
        Quantity  = request.Quantity,
        Customer  = request.CustomerEmail,
        Status    = "Confirmed",
        CreatedAt = DateTime.UtcNow
    };

    return Results.Created($"/orders/{newOrder.Id}", newOrder);
})
.WithName("CreateOrder");

app.Run();

record CreateOrderRequest(int ProductId, int Quantity, string CustomerEmail);
record InventoryItem(int ProductId, string Name, int Stock);
