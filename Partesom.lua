local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

-- Função para configurar os sons e GUI
local function iniciarGUI()
	-- Configurar pasta de sons
	local soundFolder = Instance.new("Folder")
	soundFolder.Name = "Sons"
	soundFolder.Parent = player.PlayerGui

	--  sons do ReplicatedStorage
	local somMensagem = ReplicatedStorage:WaitForChild("SomMensagem"):Clone()
	local somErro = ReplicatedStorage:WaitForChild("SomErro"):Clone()

	somMensagem.Parent = soundFolder
	somErro.Parent = soundFolder

	-- Monitorar mudanças de atributo para tocar sons
	player:GetAttributeChangedSignal("MensagemRecebida"):Connect(function()
		local valor = player:GetAttribute("MensagemRecebida")

		if valor == "valorX" then
			somMensagem:Play()
		elseif valor == "erro" then
			somErro:Play()
		end
	end)

	-- Monitorar mensagens do servidor
	local remote = ReplicatedStorage:WaitForChild("NotificarJogador")
	remote.OnClientEvent:Connect(function(tipo, conteudo)
		if tipo == "Pergunta" then
			-- Toca o som ao receber a pergunta
			somMensagem:Play()
		elseif tipo == "Resultado" and conteudo and conteudo:find("❌ Resposta incorreta!") then
			somErro:Play()
		end
	end)

	print("Sistema de GUI e sons inicializado!")
end

-- Garantir que está disponível antes de iniciar
if player:FindFirstChild("PlayerGui") then
	iniciarGUI()
else
	player:WaitForChild("PlayerGui")
	iniciarGUI()
end
