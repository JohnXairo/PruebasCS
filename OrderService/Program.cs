var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHttpClient("InventoryClient", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Services:InventoryService"] ?? "http://inventoryservice:8081");
});
builder.Services.AddHttpClient("NotificationClient", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Services:NotificationService"] ?? "http://notificationservice:8082");
});

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();

// GET /orders - lista de ordenes (simuladas)
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
.WithName("GetOrders")
.WithOpenApi();

// GET /orders/{id}
app.MapGet("/orders/{id:int}", (int id) =>
{
    if (id <= 0) return Results.NotFound();
    return Results.Ok(new { Id = id, Product = "Sample Product", Quantity = 1, Status = "Processing" });
})
.WithName("GetOrderById")
.WithOpenApi();

// POST /orders - crea una orden, verifica inventario y envia notificacion
app.MapPost("/orders", async (CreateOrderRequest request, IHttpClientFactory factory) =>
{
    // 1. Verificar inventario
    var inventoryClient = factory.CreateClient("InventoryClient");
    var inventoryResponse = await inventoryClient.GetAsync($"/inventory/{request.ProductId}");

    if (!inventoryResponse.IsSuccessStatusCode)
        return Results.Problem("Inventory service unavailable", statusCode: 503);

    var inventory = await inventoryResponse.Content.ReadFromJsonAsync<InventoryItem>();

    if (inventory is null || inventory.Stock < request.Quantity)
        return Results.BadRequest(new { Error = "Insufficient stock", Available = inventory?.Stock ?? 0 });

    // 2. Reservar stock
    var reserveResponse = await inventoryClient.PostAsJsonAsync("/inventory/reserve", new
    {
        ProductId = request.ProductId,
        Quantity  = request.Quantity
    });

    if (!reserveResponse.IsSuccessStatusCode)
        return Results.Problem("Could not reserve stock", statusCode: 503);

    // 3. Enviar notificacion
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
.WithName("CreateOrder")
.WithOpenApi();

app.Run();

record CreateOrderRequest(int ProductId, int Quantity, string CustomerEmail);
record InventoryItem(int ProductId, string Name, int Stock);
